import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spliqo/presentation/widgets/animated_paise_counter.dart';

void main() {
  group('AnimatedPaiseCounter Widget Tests', () {
    testWidgets('renders formatted paise amount accurately', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedPaiseCounter(amountPaise: 125050),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('₹1,250.50'), findsOneWidget);
    });

    testWidgets('animates smoothly from initial value to new amount',
        (tester) async {
      var currentAmount = 10000;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    AnimatedPaiseCounter(
                      amountPaise: currentAmount,
                    ),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          currentAmount = 25000;
                        });
                      },
                      child: const Text('Update'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('₹100.00'), findsOneWidget);

      // Trigger amount update
      await tester.tap(find.text('Update'));
      await tester.pump(); // Start animation

      // Settle animation to target value
      await tester.pumpAndSettle();
      expect(find.text('₹250.00'), findsOneWidget);
    });

    testWidgets('snaps immediately when disableAnimations is enabled',
        (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: AnimatedPaiseCounter(amountPaise: 45000),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('₹450.00'), findsOneWidget);
    });
  });
}
