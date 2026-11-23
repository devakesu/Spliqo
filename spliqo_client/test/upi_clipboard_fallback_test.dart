import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spliqo/domain/models/payment_intent.dart';
import 'package:spliqo/presentation/widgets/upi_clipboard_fallback_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sampleIntent = PaymentIntentModel(
    upiUri: 'upi://pay?pa=alice%40okaxis&pn=Alice+Host&am=450.00&cu=INR&tn=Spliqo',
    hostVpa: 'alice@okaxis',
    amountPaise: 45000,
    formattedAmount: '450.00',
    payeeName: 'Alice Host',
  );

  group('UpiClipboardFallbackSheet Widget Tests', () {
    testWidgets('renders host VPA, amount, instructions, and copy actions',
        (tester) async {
      var markedPaid = false;
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
        MaterialApp(
          home: Scaffold(
            body: UpiClipboardFallbackSheet(
              intent: sampleIntent,
              onMarkPaid: () => markedPaid = true,
            ),
          ),
        ),
      );

      expect(find.text('UPI App Not Available'), findsOneWidget);
      expect(find.text('alice@okaxis'), findsOneWidget);
      expect(find.text('₹450.00'), findsOneWidget);
      expect(find.text('Banking Instructions'), findsOneWidget);
      expect(
        find.textContaining('Paste the copied Host UPI ID & enter the exact amount'),
        findsOneWidget,
      );

      // Test "Copy UPI ID"
      await tester.tap(find.widgetWithText(TextButton, 'Copy UPI ID'));
      await tester.pump();
      expect(copiedString, 'alice@okaxis');

      // Test "Copy Amount"
      await tester.tap(find.widgetWithText(TextButton, 'Copy Amount'));
      await tester.pump();
      expect(copiedString, '450.00');

      // Test "Copy Intent"
      await tester.tap(find.widgetWithText(OutlinedButton, 'Copy Intent'));
      await tester.pump();
      expect(copiedString, sampleIntent.upiUri);

      // Test "Mark as Paid"
      await tester.tap(find.widgetWithText(ElevatedButton, 'Mark as Paid'));
      await tester.pump();
      expect(markedPaid, isTrue);
    });
  });
}
