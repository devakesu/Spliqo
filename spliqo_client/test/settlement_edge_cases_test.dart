import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spliqo/data/repositories/payment_repository.dart';
import 'package:spliqo/domain/models/payment_intent.dart';
import 'package:spliqo/domain/models/session.dart';
import 'package:spliqo/presentation/screens/settlement_screen.dart';
import 'package:spliqo/state/session_providers.dart';

class TestEdgePaymentRepository implements PaymentRepository {
  new();

  String? confirmedParticipantId;
  String? confirmedAction;

  @override
  Future<PaymentIntentModel> getPaymentIntent(String sessionId) async {
    return const PaymentIntentModel(
      upiUri: 'upi://pay?pa=host@okaxis&pn=Host&am=300.00&cu=INR',
      hostVpa: 'host@okaxis',
      amountPaise: 30000,
      formattedAmount: '300.00',
      payeeName: 'Host',
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
      finalAmountPaise: 30000,
      payPreference: PayPreference.selfPay,
      payStatus: action == 'confirm_paid' ? PayStatus.paid : PayStatus.unpaid,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestSettlementRoomNotifier extends SessionRoomNotifier {
  new(super.sessionId, this.initialState);

  final SessionRoomState initialState;

  @override
  SessionRoomState build() => initialState;

  @override
  Future<void> refresh() async {}
}

void main() {
  const sessionId = 'session-edge-1';

  const hostParticipant = ParticipantModel(
    id: 'part-host',
    sessionId: sessionId,
    userId: 'user-host',
    displayName: 'Host Alice',
    role: ParticipantRole.host,
  );

  const guestParticipant = ParticipantModel(
    id: 'part-guest',
    sessionId: sessionId,
    userId: 'user-guest',
    displayName: 'Guest Bob',
    role: ParticipantRole.participant,
  );

  const sampleSession = SessionModel(
    id: sessionId,
    hostId: 'user-host',
    title: 'Weekend Lunch',
    currency: 'INR',
    subtotalPaise: 60000,
    taxPaise: 0,
    serviceChargePaise: 0,
    discountPaise: 0,
    roundOffPaise: 0,
    totalPaise: 60000,
    status: SessionStatus.finalized,
    revision: 1,
  );

  group('Settlement Screen Edge Cases & Host Actions', () {
    testWidgets('host rejects pending payment with confirmation dialog',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeRepo = TestEdgePaymentRepository();
      const pendingState = SessionRoomState(
        session: sampleSession,
        participants: [hostParticipant, guestParticipant],
        settlements: [
          SettlementModel(
            participantId: 'part-host',
            sessionId: sessionId,
            finalAmountPaise: 30000,
            payPreference: PayPreference.selfPay,
            payStatus: PayStatus.paid,
          ),
          SettlementModel(
            participantId: 'part-guest',
            sessionId: sessionId,
            finalAmountPaise: 30000,
            payPreference: PayPreference.selfPay,
            payStatus: PayStatus.pending,
          ),
        ],
        currentParticipantId: 'part-host',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentRepositoryProvider.overrideWithValue(fakeRepo),
            sessionRoomProvider(sessionId).overrideWith(
              () => TestSettlementRoomNotifier(sessionId, pendingState),
            ),
          ],
          child: const MaterialApp(
            home: SettlementScreen(sessionId: sessionId),
          ),
        ),
      );

      // Verify host sees Reject button for pending guest
      expect(find.widgetWithText(OutlinedButton, 'Reject'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
      await tester.pumpAndSettle();

      // Verify confirmation dialog
      expect(find.text('Reject Payment?'), findsOneWidget);
      expect(
        find.textContaining('Mark Guest Bob back to Unpaid?'),
        findsOneWidget,
      );

      // Confirm rejection
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reject to Unpaid'));
      await tester.pumpAndSettle();

      expect(fakeRepo.confirmedParticipantId, 'part-guest');
      expect(fakeRepo.confirmedAction, 'reject_unpaid');
    });

    testWidgets('renders celebratory banner when all participants are settled',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const allSettledState = SessionRoomState(
        session: sampleSession,
        participants: [hostParticipant, guestParticipant],
        settlements: [
          SettlementModel(
            participantId: 'part-host',
            sessionId: sessionId,
            finalAmountPaise: 30000,
            payPreference: PayPreference.selfPay,
            payStatus: PayStatus.paid,
          ),
          SettlementModel(
            participantId: 'part-guest',
            sessionId: sessionId,
            finalAmountPaise: 30000,
            payPreference: PayPreference.selfPay,
            payStatus: PayStatus.paid,
          ),
        ],
        currentParticipantId: 'part-host',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentRepositoryProvider
                .overrideWithValue(TestEdgePaymentRepository()),
            sessionRoomProvider(sessionId).overrideWith(
              () => TestSettlementRoomNotifier(sessionId, allSettledState),
            ),
          ],
          child: const MaterialApp(
            home: SettlementScreen(sessionId: sessionId),
          ),
        ),
      );

      expect(find.text('All Shares Settled! 🎉'), findsOneWidget);
      expect(
        find.text(
          'Every participant has completed their share. The dining session is fully settled.',
        ),
        findsOneWidget,
      );
      expect(find.text('Export & Share Breakdown'), findsOneWidget);
    });

    testWidgets('participant directly opens fallback sheet via Copy UPI Details',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const guestUnpaidState = SessionRoomState(
        session: sampleSession,
        participants: [hostParticipant, guestParticipant],
        settlements: [
          SettlementModel(
            participantId: 'part-host',
            sessionId: sessionId,
            finalAmountPaise: 30000,
            payPreference: PayPreference.selfPay,
            payStatus: PayStatus.paid,
          ),
          SettlementModel(
            participantId: 'part-guest',
            sessionId: sessionId,
            finalAmountPaise: 30000,
            payPreference: PayPreference.selfPay,
            payStatus: PayStatus.unpaid,
          ),
        ],
        currentParticipantId: 'part-guest',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentRepositoryProvider
                .overrideWithValue(TestEdgePaymentRepository()),
            sessionRoomProvider(sessionId).overrideWith(
              () => TestSettlementRoomNotifier(sessionId, guestUnpaidState),
            ),
          ],
          child: const MaterialApp(
            home: SettlementScreen(sessionId: sessionId),
          ),
        ),
      );

      // Tap Copy UPI Details button
      expect(find.text('Copy UPI Details'), findsOneWidget);
      await tester.tap(find.text('Copy UPI Details'));
      await tester.pumpAndSettle();

      // Verify UpiClipboardFallbackSheet is displayed
      expect(find.text('UPI App Not Available'), findsOneWidget);
      expect(find.text('host@okaxis'), findsOneWidget);
      expect(find.text('Copy UPI ID'), findsOneWidget);
      expect(find.text('Copy Amount'), findsOneWidget);
    });
  });
}
