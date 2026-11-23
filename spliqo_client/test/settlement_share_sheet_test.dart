import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spliqo/domain/models/session.dart';
import 'package:spliqo/presentation/widgets/settlement_share_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = SessionModel(
    id: 's-1',
    hostId: 'u-1',
    title: 'Dinner at Paragon',
    currency: 'INR',
    subtotalPaise: 90000,
    taxPaise: 0,
    serviceChargePaise: 0,
    discountPaise: 0,
    roundOffPaise: 0,
    totalPaise: 90000,
    status: SessionStatus.finalized,
    revision: 1,
  );

  const participants = [
    ParticipantModel(
      id: 'p-1',
      sessionId: 's-1',
      userId: 'u-1',
      displayName: 'Alice Host',
      role: ParticipantRole.host,
    ),
    ParticipantModel(
      id: 'p-2',
      sessionId: 's-1',
      userId: 'u-2',
      displayName: 'Bob Diner',
      role: ParticipantRole.participant,
    ),
  ];

  const settlements = [
    SettlementModel(
      participantId: 'p-1',
      sessionId: 's-1',
      finalAmountPaise: 45000,
      payPreference: PayPreference.selfPay,
      payStatus: PayStatus.paid,
    ),
    SettlementModel(
      participantId: 'p-2',
      sessionId: 's-1',
      finalAmountPaise: 45000,
      payPreference: PayPreference.selfPay,
      payStatus: PayStatus.paid,
    ),
  ];

  group('SettlementShareSheet Widget Tests', () {
    testWidgets('renders formatted breakdown and copies summary text',
        (tester) async {
      String? copiedString;

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<dynamic, dynamic>?;
            copiedString = args?['text'] as String?;
            return null;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettlementShareSheet(
              session: session,
              participants: participants,
              settlements: settlements,
            ),
          ),
        ),
      );

      expect(find.text('Share Settlement Breakdown'), findsOneWidget);
      expect(find.text('Copy Text'), findsOneWidget);
      expect(find.text('Share to WhatsApp / Apps'), findsOneWidget);

      // Verify receipt text preview content
      expect(find.textContaining('Dinner at Paragon'), findsOneWidget);
      expect(find.textContaining('Alice Host'), findsOneWidget);
      expect(find.textContaining('Bob Diner'), findsOneWidget);
      expect(find.textContaining('2 of 2 settled'), findsOneWidget);

      // Tap Copy Text
      await tester.tap(find.widgetWithText(OutlinedButton, 'Copy Text'));
      await tester.pump();

      expect(copiedString, isNotNull);
      expect(copiedString, contains('Spliqo Bill Settlement'));
      expect(copiedString, contains('Dinner at Paragon'));
      expect(copiedString, contains('Alice Host: ₹450.00'));
      expect(copiedString, contains('Bob Diner: ₹450.00 [Paid ✓]'));
    });
  });
}
