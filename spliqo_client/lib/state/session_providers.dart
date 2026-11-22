import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spliqo/core/errors/failures.dart';
import 'package:spliqo/core/storage/secure_storage_service.dart';
import 'package:spliqo/data/datasources/api_client.dart';
import 'package:spliqo/data/datasources/supabase_client_provider.dart';
import 'package:spliqo/data/repositories/payment_repository.dart';
import 'package:spliqo/data/repositories/session_repository.dart';
import 'package:spliqo/domain/allocation/allocation.dart';
import 'package:spliqo/domain/models/session.dart';
import 'package:spliqo/presentation/widgets/connection_status_pill.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// -----------------------------------------------------------------------------
// Core Infrastructure Providers
// -----------------------------------------------------------------------------

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  final secureStorage = ref.watch(secureStorageServiceProvider);
  return ApiClient(
    tokenProvider: () async {
      final supabaseToken = supabase.auth.currentSession?.accessToken;
      if (supabaseToken != null && supabaseToken.isNotEmpty) {
        return supabaseToken;
      }
      return await secureStorage.getAuthToken();
    },
  );
});

final Provider<SessionRepository> sessionRepositoryProvider =
    Provider<SessionRepository>((ref) {
  return SessionRepository(
    apiClient: ref.watch(apiClientProvider),
    supabaseClient: ref.watch(supabaseClientProvider),
  );
});

final Provider<PaymentRepository> paymentRepositoryProvider =
    Provider<PaymentRepository>((ref) {
  return PaymentRepository(
    apiClient: ref.watch(apiClientProvider),
  );
});

// -----------------------------------------------------------------------------
// Session State & Realtime Sync Engine (Section 9 Standards)
// -----------------------------------------------------------------------------

class SessionRoomState {
  const new({
    this.session,
    this.participants = const [],
    this.claims = const [],
    this.settlements = const [],
    this.currentParticipantId,
    this.connectionStatus = RealtimeConnectionStatus.live,
    this.isLoading = false,
    this.errorMessage,
  });

  final SessionModel? session;
  final List<ParticipantModel> participants;
  final List<ClaimModel> claims;
  final List<SettlementModel> settlements;
  final String? currentParticipantId;
  final RealtimeConnectionStatus connectionStatus;
  final bool isLoading;
  final String? errorMessage;

  ParticipantModel? get currentParticipant {
    if (currentParticipantId == null) return null;
    return participants.cast<ParticipantModel?>().firstWhere(
          (p) => p?.id == currentParticipantId,
          orElse: () => null,
        );
  }

  SettlementModel? get currentSettlement {
    if (currentParticipantId == null) return null;
    return settlements.cast<SettlementModel?>().firstWhere(
          (s) => s?.participantId == currentParticipantId,
          orElse: () => null,
        );
  }

  bool get isHost => currentParticipant?.role == ParticipantRole.host;
  bool get isSelectionCompleted => currentParticipant?.isSelectionCompleted ?? false;

  bool isItemClaimedByMe(String itemId) {
    if (currentParticipantId == null) return false;
    return claims.any(
      (c) => c.itemId == itemId && c.participantId == currentParticipantId,
    );
  }

  List<ParticipantModel> getClaimantsForItem(String itemId) {
    final claimantIds = claims
        .where((c) => c.itemId == itemId)
        .map((c) => c.participantId)
        .toSet();
    return participants.where((p) => claimantIds.contains(p.id)).toList();
  }

  /// 0ms instant running estimated share calculation using pure Dart Allocation Engine.
  int get estimatedSharePaise {
    if (session == null || currentParticipantId == null || session!.items.isEmpty) {
      return 0;
    }

    var myItemsPaise = 0;
    for (final item in session!.items) {
      final claimants = claims
          .where((c) => c.itemId == item.id)
          .map((c) => c.participantId)
          .toList();
      if (claimants.contains(currentParticipantId)) {
        myItemsPaise += item.pricePaise ~/ claimants.length;
      }
    }

    if (myItemsPaise == 0) return 0;

    try {
      return estimateSharePaise(
        itemsPaise: myItemsPaise,
        subtotalPaise: session!.subtotalPaise,
        totalPaise: session!.totalPaise,
      );
    } on Exception catch (_) {
      return 0;
    }
  }

  SessionRoomState copyWith({
    SessionModel? session,
    List<ParticipantModel>? participants,
    List<ClaimModel>? claims,
    List<SettlementModel>? settlements,
    String? currentParticipantId,
    RealtimeConnectionStatus? connectionStatus,
    bool? isLoading,
    String? errorMessage,
  }) {
    return SessionRoomState(
      session: session ?? this.session,
      participants: participants ?? this.participants,
      claims: claims ?? this.claims,
      settlements: settlements ?? this.settlements,
      currentParticipantId: currentParticipantId ?? this.currentParticipantId,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class SessionRoomNotifier extends Notifier<SessionRoomState> {
  new(this.sessionId);

  final String sessionId;
  RealtimeChannel? _channel;
  Timer? _debounceTimer;

  SessionRepository get sessionRepository => ref.read(sessionRepositoryProvider);
  SupabaseClient get supabaseClient => ref.read(supabaseClientProvider);

  @override
  SessionRoomState build() {
    final client = supabaseClient;
    ref.onDispose(() {
      _debounceTimer?.cancel();
      if (_channel != null) {
        unawaited(client.removeChannel(_channel!));
      }
    });

    unawaited(_init());
    return const SessionRoomState(isLoading: true);
  }

  Future<void> _init() async {
    await _fetchInitialData();
    try {
      _subscribeRealtime();
    } on Object catch (_) {
      // Realtime subscription unavailable or mocked
    }
  }

  Future<void> _fetchInitialData() async {
    try {
      final session = await sessionRepository.fetchSession(sessionId);
      final participants = await sessionRepository.fetchParticipants(sessionId);
      final claims = await sessionRepository.fetchClaims(sessionId);
      final settlements = await sessionRepository.fetchSettlements(sessionId);

      final currentUserId = supabaseClient.auth.currentUser?.id;
      final current = participants.cast<ParticipantModel?>().firstWhere(
            (p) => p?.userId == currentUserId,
            orElse: () => participants.isNotEmpty ? participants.first : null,
          );

      state = state.copyWith(
        session: session,
        participants: participants,
        claims: claims,
        settlements: settlements,
        currentParticipantId: current?.id,
        isLoading: false,
      );
    } on Object catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load session: $e',
      );
    }
  }

  /// Section 9: 150ms debounce invalidation refetch through RLS.
  void _subscribeRealtime() {
    _channel = supabaseClient
        .channel('session_$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'item_claims',
          callback: (_) => _onInvalidationSignal(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'session_participants',
          callback: (_) => _onInvalidationSignal(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'sessions',
          callback: (_) => _onInvalidationSignal(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'participant_settlements',
          callback: (_) => _onInvalidationSignal(),
        );

    _channel?.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        state = state.copyWith(
          connectionStatus: RealtimeConnectionStatus.live,
        );
      } else if (status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        state = state.copyWith(
          connectionStatus: RealtimeConnectionStatus.reconnecting,
        );
      }
    });
  }

  void _onInvalidationSignal() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      unawaited(_reReadThroughRLS());
    });
  }

  Future<void> _reReadThroughRLS() async {
    try {
      final session = await sessionRepository.fetchSession(sessionId);
      final participants = await sessionRepository.fetchParticipants(sessionId);
      final claims = await sessionRepository.fetchClaims(sessionId);
      final settlements = await sessionRepository.fetchSettlements(sessionId);

      state = state.copyWith(
        session: session,
        participants: participants,
        claims: claims,
        settlements: settlements,
        connectionStatus: RealtimeConnectionStatus.live,
      );
    } on Exception catch (_) {
      state = state.copyWith(
        connectionStatus: RealtimeConnectionStatus.offline,
      );
    }
  }

  /// Optimistic Claim Toggle (Section 9.6 of Standards):
  /// Toggles claim locally immediately for same-frame UI update, then commits to Supabase.
  /// On trigger or RLS rejection (e.g. locked selection), rolls back and surfaces error.
  Future<void> toggleClaim(String itemId) async {
    final participantId = state.currentParticipantId;
    if (participantId == null) return;

    if (state.isSelectionCompleted) {
      state = state.copyWith(errorMessage: 'Your selection is locked.');
      return;
    }

    final isClaimed = state.isItemClaimedByMe(itemId);
    final previousClaims = List<ClaimModel>.from(state.claims);

    if (isClaimed) {
      state = state.copyWith(
        claims: state.claims
            .where((c) => !(c.itemId == itemId && c.participantId == participantId))
            .toList(),
      );
    } else {
      final optimisticClaim = ClaimModel(
        id: 'optimistic_${DateTime.now().millisecondsSinceEpoch}',
        sessionId: sessionId,
        itemId: itemId,
        participantId: participantId,
        source: ClaimSource.self,
      );
      state = state.copyWith(claims: [...state.claims, optimisticClaim]);
    }

    try {
      if (isClaimed) {
        await sessionRepository.unclaimItem(
          sessionId: sessionId,
          itemId: itemId,
          participantId: participantId,
        );
      } else {
        await sessionRepository.claimItem(
          sessionId: sessionId,
          itemId: itemId,
          participantId: participantId,
        );
      }
    } on Exception catch (_) {
      state = state.copyWith(
        claims: previousClaims,
        errorMessage: 'Selection is locked or room has advanced.',
      );
    }
  }

  Future<void> completeSelection() async {
    try {
      await sessionRepository.completeMySelection(sessionId);
      await _reReadThroughRLS();
    } on Failure catch (f) {
      state = state.copyWith(errorMessage: f.message);
    } on Exception catch (e) {
      state = state.copyWith(errorMessage: 'Could not complete selection: $e');
    }
  }

  /// Host force lock room -> reviewing (STANDARDS.md Section 3.3).
  Future<void> lockRoom() async {
    try {
      final updated = await sessionRepository.lockRoom(sessionId);
      state = state.copyWith(session: updated);
      await _reReadThroughRLS();
    } on Failure catch (f) {
      state = state.copyWith(errorMessage: f.message);
    } on Exception catch (e) {
      state = state.copyWith(errorMessage: 'Could not lock room: $e');
    }
  }

  /// Host reopen room before finalization (STANDARDS.md Section 3.3).
  Future<void> reopenRoom() async {
    try {
      final updated = await sessionRepository.reopenRoom(sessionId);
      state = state.copyWith(session: updated);
      await _reReadThroughRLS();
    } on Failure catch (f) {
      state = state.copyWith(errorMessage: f.message);
    } on Exception catch (e) {
      state = state.copyWith(errorMessage: 'Could not reopen room: $e');
    }
  }

  Future<void> refresh() async {
    await _fetchInitialData();
  }
}

// Riverpod 3 internal family builder type is not publicly exported.
// ignore: specify_nonobvious_property_types
final _sessionRoomFamily =
    NotifierProvider.autoDispose.family<SessionRoomNotifier, SessionRoomState, String>(
  SessionRoomNotifier.new,
);

NotifierProvider<SessionRoomNotifier, SessionRoomState> sessionRoomProvider(
  String sessionId,
) =>
    _sessionRoomFamily(sessionId);
