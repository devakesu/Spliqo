import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spliqo/data/repositories/session_repository.dart';
import 'package:spliqo/domain/models/session.dart';
import 'package:spliqo/presentation/screens/active_room_screen.dart';
import 'package:spliqo/presentation/screens/host_review_screen.dart';
import 'package:spliqo/state/session_providers.dart';

class TestHostControlsNotifier extends SessionRoomNotifier {
  new(super.sessionId, this.initialState);

  final SessionRoomState initialState;
  bool lockCalled = false;
  bool reopenCalled = false;

  @override
  SessionRoomState build() => initialState;

  @override
  Future<void> lockRoom() async {
    lockCalled = true;
    state = state.copyWith(
      session: state.session?.copyWith(status: SessionStatus.reviewing),
    );
  }

  @override
  Future<void> reopenRoom() async {
    reopenCalled = true;
    state = state.copyWith(
      session: state.session?.copyWith(status: SessionStatus.active),
    );
  }
}

class FakeHostSessionRepo implements SessionRepository {
  bool repoReopenCalled = false;

  @override
  Future<SessionModel> reopenRoom(String sessionId) async {
    repoReopenCalled = true;
    return const SessionModel(
      id: 'sess-1',
      hostId: 'u-host',
      title: 'Lunch',
      currency: 'INR',
      subtotalPaise: 1000,
      taxPaise: 0,
      serviceChargePaise: 0,
      discountPaise: 0,
      roundOffPaise: 0,
      totalPaise: 1000,
      status: SessionStatus.active,
      revision: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const sessionId = 'sess-123';

  const hostParticipant = ParticipantModel(
    id: 'p-host',
    sessionId: sessionId,
    userId: 'u-host',
    displayName: 'Alice Host',
    role: ParticipantRole.host,
  );

  const guestParticipant = ParticipantModel(
    id: 'p-guest',
    sessionId: sessionId,
    userId: 'u-guest',
    displayName: 'Bob Guest',
    role: ParticipantRole.participant,
  );

  const activeSession = SessionModel(
    id: sessionId,
    hostId: 'u-host',
    title: 'Pizza Party',
    currency: 'INR',
    subtotalPaise: 50000,
    taxPaise: 0,
    serviceChargePaise: 0,
    discountPaise: 0,
    roundOffPaise: 0,
    totalPaise: 50000,
    status: SessionStatus.active,
    revision: 0,
    items: [
      BillItemModel(
        id: 'i-1',
        sessionId: sessionId,
        name: 'Margherita Pizza',
        pricePaise: 50000,
        position: 0,
      ),
    ],
  );

  group('Active Room Host Controls & Reopen Tests', () {
    testWidgets(
        'host triggers Force Lock Room from AppBar with confirmation dialog',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = TestHostControlsNotifier(
        sessionId,
        const SessionRoomState(
          session: activeSession,
          participants: [hostParticipant, guestParticipant],
          currentParticipantId: 'p-host',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRoomProvider(sessionId).overrideWith(() => notifier),
          ],
          child: const MaterialApp(
            home: ActiveRoomScreen(sessionId: sessionId),
          ),
        ),
      );

      // Verify Force Lock Room icon exists for host
      final lockButton = find.byTooltip('Force Lock Room');
      expect(lockButton, findsOneWidget);

      await tester.tap(lockButton);
      await tester.pumpAndSettle();

      // Verify confirmation dialog
      expect(find.text('Force Lock Room?'), findsOneWidget);
      expect(
        find.textContaining('Any participants who have not tapped "Done Selecting"'),
        findsOneWidget,
      );

      // Confirm lock
      await tester.tap(find.widgetWithText(ElevatedButton, 'Lock Room'));
      await tester.pumpAndSettle();

      expect(notifier.lockCalled, isTrue);
    });

    testWidgets('non-host does not see Force Lock Room button', (tester) async {
      final guestNotifier = TestHostControlsNotifier(
        sessionId,
        const SessionRoomState(
          session: activeSession,
          participants: [hostParticipant, guestParticipant],
          currentParticipantId: 'p-guest',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRoomProvider(sessionId).overrideWith(() => guestNotifier),
          ],
          child: const MaterialApp(
            home: ActiveRoomScreen(sessionId: sessionId),
          ),
        ),
      );

      expect(find.byTooltip('Force Lock Room'), findsNothing);
    });

    testWidgets('host reopens room from HostReviewScreen with confirmation',
        (tester) async {
      final fakeRepo = FakeHostSessionRepo();
      final reviewingNotifier = TestHostControlsNotifier(
        sessionId,
        SessionRoomState(
          session: activeSession.copyWith(status: SessionStatus.reviewing),
          participants: const [hostParticipant, guestParticipant],
          currentParticipantId: 'p-host',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRepositoryProvider.overrideWithValue(fakeRepo),
            sessionRoomProvider(sessionId).overrideWith(() => reviewingNotifier),
          ],
          child: const MaterialApp(
            home: HostReviewScreen(sessionId: sessionId),
          ),
        ),
      );

      // Verify Reopen action exists in AppBar
      expect(find.text('Reopen'), findsOneWidget);

      await tester.tap(find.text('Reopen'));
      await tester.pumpAndSettle();

      // Verify confirmation dialog
      expect(find.text('Reopen Room?'), findsOneWidget);
      expect(
        find.textContaining('Reopening the room moves the session back to active selection'),
        findsOneWidget,
      );

      // Confirm reopen
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reopen Room'));
      await tester.pumpAndSettle();

      expect(fakeRepo.repoReopenCalled, isTrue);
    });
  });
}
