import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:spliqo/data/repositories/payment_repository.dart';
import 'package:spliqo/data/repositories/session_repository.dart';
import 'package:spliqo/domain/models/payment_intent.dart';
import 'package:spliqo/domain/models/session.dart';
import 'package:spliqo/presentation/screens/active_room_screen.dart';
import 'package:spliqo/presentation/screens/host_review_screen.dart';
import 'package:spliqo/presentation/screens/receipt_review_screen.dart';
import 'package:spliqo/presentation/screens/settlement_screen.dart';
import 'package:spliqo/state/session_providers.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

// -----------------------------------------------------------------------------
// Test Doubles (Fakes)
// -----------------------------------------------------------------------------

class FakeUrlLauncherPlatform extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  bool canLaunchResult = false;
  String? launchedUrl;

  @override
  Future<bool> canLaunch(String url) async => canLaunchResult;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrl = url;
    return true;
  }

  @override
  LinkDelegate? get linkDelegate => null;
}

class FakeSessionRepository implements SessionRepository {
  new({
    this.session,
    List<ParticipantModel>? participants,
    List<ClaimModel>? claims,
    List<SettlementModel>? settlements,
  })  : participants = participants ?? [],
        claims = claims ?? [],
        settlements = settlements ?? [];

  SessionModel? session;
  List<ParticipantModel> participants;
  List<ClaimModel> claims;
  List<SettlementModel> settlements;

  bool activated = false;
  bool finalized = false;
  bool locked = false;
  bool reopened = false;
  String? resolvedAction;
  String? resolvedTargetParticipantId;
  List<String>? resolvedItemIds;

  @override
  Future<Map<String, dynamic>> parseReceipt({
    required List<int> imageBytes,
    required String filename,
    required String hostDisplayName,
  }) async {
    return {
      'session': session?.toJson() ?? {},
      'needs_review': true,
    };
  }

  @override
  Future<SessionModel> createDraftSession(Map<String, dynamic> draftData) async {
    return session!;
  }

  @override
  Future<SessionModel> updateDraftSession(
    String sessionId,
    Map<String, dynamic> draftData,
  ) async {
    return session!;
  }

  @override
  Future<SessionModel> activateSession(String sessionId) async {
    activated = true;
    session = session?.copyWith(status: SessionStatus.active);
    return session!;
  }

  @override
  Future<SessionModel> lockRoom(String sessionId) async {
    locked = true;
    session = session?.copyWith(status: SessionStatus.reviewing);
    return session!;
  }

  @override
  Future<SessionModel> reopenRoom(String sessionId) async {
    reopened = true;
    session = session?.copyWith(status: SessionStatus.active);
    return session!;
  }

  @override
  Future<Map<String, dynamic>> resolveUnclaimed({
    required String sessionId,
    required String action,
    String? targetParticipantId,
    List<String>? itemIds,
  }) async {
    resolvedAction = action;
    resolvedTargetParticipantId = targetParticipantId;
    resolvedItemIds = itemIds;
    return {'status': 'ok', 'resolved_count': itemIds?.length ?? 1};
  }

  @override
  Future<Map<String, dynamic>> finalizeSession(String sessionId) async {
    finalized = true;
    session = session?.copyWith(status: SessionStatus.finalized);
    return {'status': 'finalized'};
  }

  @override
  Future<SessionModel> fetchSession(String sessionId) async {
    return session!;
  }

  @override
  Future<List<ParticipantModel>> fetchParticipants(String sessionId) async {
    return participants;
  }

  @override
  Future<List<ClaimModel>> fetchClaims(String sessionId) async {
    return claims;
  }

  @override
  Future<List<SettlementModel>> fetchSettlements(String sessionId) async {
    return settlements;
  }

  @override
  Future<void> claimItem({
    required String sessionId,
    required String itemId,
    required String participantId,
  }) async {
    claims.add(
      ClaimModel(
        id: 'claim_${claims.length + 1}',
        sessionId: sessionId,
        itemId: itemId,
        participantId: participantId,
        source: ClaimSource.self,
      ),
    );
  }

  @override
  Future<void> unclaimItem({
    required String sessionId,
    required String itemId,
    required String participantId,
  }) async {
    claims.removeWhere(
      (c) =>
          c.sessionId == sessionId &&
          c.itemId == itemId &&
          c.participantId == participantId,
    );
  }

  @override
  Future<void> completeMySelection(String sessionId) async {
    participants = participants.map((p) {
      if (p.role == ParticipantRole.participant) {
        return p.copyWith(selectionCompletedAt: DateTime.now());
      }
      return p;
    }).toList();
  }
}

class FakePaymentRepository implements PaymentRepository {
  String upiUri =
      'upi://pay?pa=host%40okhdfcbank&pn=Host+Alice&am=350.00&cu=INR';
  PayPreference? lastUpdatedPreference;
  bool pendingMarked = false;
  String? confirmedParticipantId;
  String? confirmedAction;

  @override
  Future<PaymentIntentModel> getPaymentIntent(String sessionId) async {
    return PaymentIntentModel(
      upiUri: upiUri,
      hostVpa: 'host@okhdfcbank',
      amountPaise: 35000,
      formattedAmount: '350.00',
      payeeName: 'Host Alice',
    );
  }

  @override
  Future<SettlementModel> updatePaymentPreference({
    required String sessionId,
    required PayPreference preference,
  }) async {
    lastUpdatedPreference = preference;
    return SettlementModel(
      participantId: 'part-guest',
      sessionId: sessionId,
      finalAmountPaise: 35000,
      payPreference: preference,
      payStatus: PayStatus.unpaid,
    );
  }

  @override
  Future<SettlementModel> markPaymentPending(String sessionId) async {
    pendingMarked = true;
    return const SettlementModel(
      participantId: 'part-guest',
      sessionId: 'sess-1',
      finalAmountPaise: 35000,
      payPreference: PayPreference.selfPay,
      payStatus: PayStatus.pending,
    );
  }

  @override
  Future<SettlementModel> confirmPayment({
    required String sessionId,
    required String targetParticipantId,
    required String action,
  }) async {
    confirmedParticipantId = targetParticipantId;
    confirmedAction = action;
    return SettlementModel(
      participantId: targetParticipantId,
      sessionId: sessionId,
      finalAmountPaise: 35000,
      payPreference: action == 'confirm_waived'
          ? PayPreference.hostPays
          : PayPreference.selfPay,
      payStatus: action == 'confirm_waived' ? PayStatus.waived : PayStatus.paid,
    );
  }

  @override
  Future<void> setPayoutProfile(String upiId) async {}
}

class TestSessionRoomNotifier extends SessionRoomNotifier {
  new(super.sessionId, this.initialTestState);

  final SessionRoomState initialTestState;

  @override
  SessionRoomState build() {
    return initialTestState;
  }

  @override
  Future<void> toggleClaim(String itemId) async {
    final participantId = state.currentParticipantId;
    if (participantId == null) return;
    if (state.isSelectionCompleted) return;

    final isClaimed = state.isItemClaimedByMe(itemId);
    if (isClaimed) {
      state = state.copyWith(
        claims: state.claims
            .where((c) =>
                !(c.itemId == itemId && c.participantId == participantId))
            .toList(),
      );
    } else {
      final newClaim = ClaimModel(
        id: 'claim_opt_${state.claims.length + 1}',
        sessionId: sessionId,
        itemId: itemId,
        participantId: participantId,
        source: ClaimSource.self,
      );
      state = state.copyWith(claims: [...state.claims, newClaim]);
    }
  }

  @override
  Future<void> completeSelection() async {
    final updatedParticipants = state.participants.map((p) {
      if (p.id == state.currentParticipantId) {
        return p.copyWith(selectionCompletedAt: DateTime.now());
      }
      return p;
    }).toList();

    state = state.copyWith(participants: updatedParticipants);
  }

  @override
  Future<void> refresh() async {}
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

void main() {
  const sessionId = 'session-test-123';

  const sampleItems = [
    BillItemModel(
      id: 'item-1',
      sessionId: sessionId,
      position: 0,
      name: 'Paneer Butter Masala',
      pricePaise: 40000, // ₹400.00
    ),
    BillItemModel(
      id: 'item-2',
      sessionId: sessionId,
      position: 1,
      name: 'Garlic Naan',
      pricePaise: 10000, // ₹100.00
    ),
    BillItemModel(
      id: 'item-3',
      sessionId: sessionId,
      position: 2,
      name: 'Mango Lassi',
      pricePaise: 15000, // ₹150.00
    ),
  ];

  const sampleDraftSession = SessionModel(
    id: sessionId,
    hostId: 'user-host',
    title: 'Dinner at Paragon',
    currency: 'INR',
    status: SessionStatus.draft,
    subtotalPaise: 65000,
    taxPaise: 3250, // 5% GST
    serviceChargePaise: 0,
    discountPaise: 0,
    roundOffPaise: 0,
    totalPaise: 68250,
    revision: 1,
    items: sampleItems,
  );

  final sampleActiveSession = sampleDraftSession.copyWith(
    status: SessionStatus.active,
  );

  final sampleReviewingSession = sampleDraftSession.copyWith(
    status: SessionStatus.reviewing,
  );

  final sampleFinalizedSession = sampleDraftSession.copyWith(
    status: SessionStatus.finalized,
  );

  const hostParticipant = ParticipantModel(
    id: 'part-host',
    sessionId: sessionId,
    userId: 'user-host',
    role: ParticipantRole.host,
    displayName: 'Host Alice',
  );

  const guestParticipant = ParticipantModel(
    id: 'part-guest',
    sessionId: sessionId,
    userId: 'user-guest',
    role: ParticipantRole.participant,
    displayName: 'Guest Bob',
  );

  late FakeUrlLauncherPlatform fakeUrlLauncher;

  setUp(() {
    fakeUrlLauncher = FakeUrlLauncherPlatform();
    UrlLauncherPlatform.instance = fakeUrlLauncher;
  });

  group('Screen 1: ReceiptReviewScreen Flow Tests', () {
    testWidgets('renders draft receipt details and line items accurately',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeRepo = FakeSessionRepository(session: sampleDraftSession);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(
            home: ReceiptReviewScreen(initialSession: sampleDraftSession),
          ),
        ),
      );

      expect(find.text('Receipt Draft Review'), findsOneWidget);
      expect(find.text('Dinner at Paragon'), findsOneWidget);
      expect(find.text('DRAFT'), findsOneWidget);
      expect(find.text('Paneer Butter Masala'), findsOneWidget);
      expect(find.text('₹400.00'), findsOneWidget);
      expect(find.text('Garlic Naan'), findsOneWidget);
      expect(find.text('₹100.00'), findsOneWidget);
      expect(find.text('Mango Lassi'), findsOneWidget);
      expect(find.text('₹150.00'), findsOneWidget);
      expect(find.text('₹650.00'), findsOneWidget); // Subtotal
      expect(find.text('₹32.50'), findsOneWidget); // Tax
      expect(find.text('₹682.50'), findsOneWidget); // Total
      expect(
        find.text('Activate Session & Invite Participants'),
        findsOneWidget,
      );
    });

    testWidgets('tapping activate triggers activateSession on repository',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeRepo = FakeSessionRepository(session: sampleDraftSession);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRepositoryProvider.overrideWithValue(fakeRepo),
            sessionRoomProvider(sessionId).overrideWith(
              () => TestSessionRoomNotifier(
                sessionId,
                SessionRoomState(
                  session: sampleActiveSession,
                  participants: const [hostParticipant],
                  currentParticipantId: hostParticipant.id,
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: ReceiptReviewScreen(initialSession: sampleDraftSession),
          ),
        ),
      );

      final activateBtn = find.text('Activate Session & Invite Participants');
      await tester.tap(activateBtn);
      await tester.pumpAndSettle();

      expect(fakeRepo.activated, isTrue);
      // Navigated to ActiveRoomScreen
      expect(find.byType(ActiveRoomScreen), findsOneWidget);
    });
  });

  group('Screen 2: ActiveRoomScreen & Live Item Selection Tests', () {
    testWidgets(
        'renders active room, items, sticky estimated footer, and handles live claiming',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final initialState = SessionRoomState(
        session: sampleActiveSession,
        participants: const [hostParticipant, guestParticipant],
        currentParticipantId: guestParticipant.id,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRoomProvider(sessionId).overrideWith(
              () => TestSessionRoomNotifier(sessionId, initialState),
            ),
          ],
          child: const MaterialApp(
            home: ActiveRoomScreen(sessionId: sessionId),
          ),
        ),
      );

      expect(find.text('Dinner at Paragon'), findsOneWidget);
      expect(find.text('Live session'), findsOneWidget);
      expect(find.text('₹682.50'), findsOneWidget); // Total restaurant bill
      expect(find.text('2 Participants'), findsOneWidget);

      // Initially zero share
      expect(find.text('YOUR CURRENT ESTIMATED SHARE'), findsOneWidget);
      expect(find.text('₹0.00'), findsOneWidget);
      expect(find.text('Estimated'), findsOneWidget);
      expect(find.text('Done Selecting'), findsOneWidget);

      // Tap first item (Paneer Butter Masala: ₹400.00)
      // Estimated share = 40000 * 68250 / 65000 = 42000 paise = ₹420.00
      await tester.tap(find.text('Paneer Butter Masala'));
      await tester.pumpAndSettle();

      // Estimated share should now be ₹420.00
      expect(find.text('₹420.00'), findsOneWidget);

      // Tap "Done Selecting"
      await tester.tap(find.text('Done Selecting'));
      await tester.pumpAndSettle();

      // Should now freeze selection
      expect(find.text('Selection Completed'), findsOneWidget);
      expect(
        find.text(
          'Your selections are locked. Share updates live as others finish.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('displays reviewing banner for host when session is reviewing',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final reviewingState = SessionRoomState(
        session: sampleReviewingSession,
        participants: [
          hostParticipant.copyWith(
            selectionCompletedAt: DateTime.now(),
          ),
          guestParticipant.copyWith(
            selectionCompletedAt: DateTime.now(),
          ),
        ],
        claims: const [
          ClaimModel(
            id: 'c-1',
            sessionId: sessionId,
            itemId: 'item-1',
            participantId: 'part-host',
            source: ClaimSource.self,
          ),
        ],
        currentParticipantId: hostParticipant.id,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRoomProvider(sessionId).overrideWith(
              () => TestSessionRoomNotifier(sessionId, reviewingState),
            ),
          ],
          child: const MaterialApp(
            home: ActiveRoomScreen(sessionId: sessionId),
          ),
        ),
      );

      expect(find.text('Reviewing Phase'), findsOneWidget);
      expect(
        find.text(
          'All participants finished! Proceed to resolve unallocated costs.',
        ),
        findsOneWidget,
      );
      expect(find.text('Review Bill'), findsOneWidget);
    });
  });

  group('Screen 3: HostReviewScreen & Unclaimed Resolution Tests', () {
    testWidgets('displays unresolved items warning and disables finalise',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeRepo = FakeSessionRepository(
        session: sampleReviewingSession,
        participants: const [hostParticipant, guestParticipant],
        claims: const [
          ClaimModel(
            id: 'c-1',
            sessionId: sessionId,
            itemId: 'item-1',
            participantId: 'part-host',
            source: ClaimSource.self,
          ),
          // item-2 and item-3 remain unclaimed
        ],
      );

      final stateWithUnclaimed = SessionRoomState(
        session: sampleReviewingSession,
        participants: const [hostParticipant, guestParticipant],
        claims: fakeRepo.claims,
        currentParticipantId: hostParticipant.id,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRepositoryProvider.overrideWithValue(fakeRepo),
            sessionRoomProvider(sessionId).overrideWith(
              () => TestSessionRoomNotifier(sessionId, stateWithUnclaimed),
            ),
          ],
          child: const MaterialApp(
            home: HostReviewScreen(sessionId: sessionId),
          ),
        ),
      );

      expect(find.text('Host Final Review'), findsOneWidget);
      expect(find.text('Unresolved Items (2)'), findsOneWidget);
      expect(find.text('Resolve Unclaimed Items'), findsOneWidget);

      // Finalise button should be disabled
      final finalizeButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Finalise Bill & Generate Shares'),
      );
      expect(finalizeButton.onPressed, isNull);
    });

    testWidgets('resolves unclaimed items and finalises session',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeRepo = FakeSessionRepository(
        session: sampleReviewingSession,
        participants: const [hostParticipant, guestParticipant],
        claims: const [
          // All items claimed
          ClaimModel(
            id: 'c-1',
            sessionId: sessionId,
            itemId: 'item-1',
            participantId: 'part-host',
            source: ClaimSource.self,
          ),
          ClaimModel(
            id: 'c-2',
            sessionId: sessionId,
            itemId: 'item-2',
            participantId: 'part-guest',
            source: ClaimSource.self,
          ),
          ClaimModel(
            id: 'c-3',
            sessionId: sessionId,
            itemId: 'item-3',
            participantId: 'part-guest',
            source: ClaimSource.self,
          ),
        ],
      );

      final fullyClaimedState = SessionRoomState(
        session: sampleReviewingSession,
        participants: const [hostParticipant, guestParticipant],
        claims: fakeRepo.claims,
        settlements: const [
          SettlementModel(
            participantId: 'part-host',
            sessionId: sessionId,
            finalAmountPaise: 42000,
            payPreference: PayPreference.selfPay,
            payStatus: PayStatus.paid,
          ),
          SettlementModel(
            participantId: 'part-guest',
            sessionId: sessionId,
            finalAmountPaise: 26250,
            payPreference: PayPreference.selfPay,
            payStatus: PayStatus.unpaid,
          ),
        ],
        currentParticipantId: hostParticipant.id,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRepositoryProvider.overrideWithValue(fakeRepo),
            paymentRepositoryProvider
                .overrideWithValue(FakePaymentRepository()),
            sessionRoomProvider(sessionId).overrideWith(
              () => TestSessionRoomNotifier(sessionId, fullyClaimedState),
            ),
          ],
          child: const MaterialApp(
            home: HostReviewScreen(sessionId: sessionId),
          ),
        ),
      );

      expect(find.text('Unresolved Items'), findsNothing);

      final finalizeBtn =
          find.widgetWithText(ElevatedButton, 'Finalise Bill & Generate Shares');
      expect(tester.widget<ElevatedButton>(finalizeBtn).onPressed, isNotNull);

      await tester.tap(finalizeBtn);
      await tester.pumpAndSettle();

      expect(fakeRepo.finalized, isTrue);
      expect(find.byType(SettlementScreen), findsOneWidget);
    });
  });

  group('Screen 4: SettlementScreen & Payment Intent Tests', () {
    testWidgets(
        'renders immutable final shares, handles participant payment preference and upi intent',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakePaymentRepo = FakePaymentRepository();

      final settledState = SessionRoomState(
        session: sampleFinalizedSession,
        participants: const [hostParticipant, guestParticipant],
        settlements: const [
          SettlementModel(
            participantId: 'part-host',
            sessionId: sessionId,
            finalAmountPaise: 42000,
            payPreference: PayPreference.selfPay,
            payStatus: PayStatus.paid,
          ),
          SettlementModel(
            participantId: 'part-guest',
            sessionId: sessionId,
            finalAmountPaise: 26250,
            payPreference: PayPreference.selfPay,
            payStatus: PayStatus.unpaid,
          ),
        ],
        currentParticipantId: guestParticipant.id,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentRepositoryProvider.overrideWithValue(fakePaymentRepo),
            sessionRoomProvider(sessionId).overrideWith(
              () => TestSessionRoomNotifier(sessionId, settledState),
            ),
          ],
          child: const MaterialApp(
            home: SettlementScreen(sessionId: sessionId),
          ),
        ),
      );

      expect(find.text('Final Settlement'), findsOneWidget);
      expect(find.text('Bill Finalised'), findsOneWidget);
      expect(find.text('YOUR FINAL SHARE'), findsOneWidget);
      expect(find.text('Final'), findsOneWidget);
      expect(find.text('₹262.50'), findsNWidgets(2)); // Header share & list share

      // Preference choice chips
      expect(find.text('Pay my share'), findsOneWidget);
      expect(find.text('Let host cover'), findsOneWidget);

      // Actions for self_pay + unpaid
      expect(find.text('Pay with UPI App'), findsOneWidget);
      expect(find.text('Mark as Paid (Notify Host)'), findsOneWidget);

      // Test "Mark as Paid"
      await tester.tap(find.text('Mark as Paid (Notify Host)'));
      await tester.pump();
      expect(fakePaymentRepo.pendingMarked, isTrue);

      // Test "Pay with UPI App"
      fakeUrlLauncher.canLaunchResult = false;
      await tester.tap(find.text('Pay with UPI App'));
      await tester.pumpAndSettle();

      // Since canLaunch is false, fallback dialog opens
      expect(find.text('UPI App Not Available'), findsOneWidget);
      expect(find.text('Copy Intent'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('host views participant payments and confirms or waives',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakePaymentRepo = FakePaymentRepository();

      final hostSettledState = SessionRoomState(
        session: sampleFinalizedSession,
        participants: const [hostParticipant, guestParticipant],
        settlements: const [
          SettlementModel(
            participantId: 'part-host',
            sessionId: sessionId,
            finalAmountPaise: 42000,
            payPreference: PayPreference.selfPay,
            payStatus: PayStatus.paid,
          ),
          SettlementModel(
            participantId: 'part-guest',
            sessionId: sessionId,
            finalAmountPaise: 26250,
            payPreference: PayPreference.selfPay,
            payStatus: PayStatus.pending,
          ),
        ],
        currentParticipantId: hostParticipant.id,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentRepositoryProvider.overrideWithValue(fakePaymentRepo),
            sessionRoomProvider(sessionId).overrideWith(
              () => TestSessionRoomNotifier(sessionId, hostSettledState),
            ),
          ],
          child: const MaterialApp(
            home: SettlementScreen(sessionId: sessionId),
          ),
        ),
      );

      expect(find.text('Participant Settlements & Actions'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);

      // Host sees "Confirm Paid" button for pending guest
      final confirmBtn = find.text('Confirm Paid');
      expect(confirmBtn, findsOneWidget);

      await tester.tap(confirmBtn);
      await tester.pump();

      expect(fakePaymentRepo.confirmedParticipantId, equals('part-guest'));
      expect(fakePaymentRepo.confirmedAction, equals('confirm_paid'));
    });
  });
}
