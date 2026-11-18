import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spliqo/core/utils/currency_formatter.dart';
import 'package:spliqo/domain/models/session.dart';
import 'package:spliqo/presentation/widgets/bill_item_tile.dart';
import 'package:spliqo/presentation/widgets/estimated_share_footer.dart';
import 'package:spliqo/presentation/widgets/participant_status_row.dart';

void main() {
  group('Money Formatting and CurrencyFormatter tests', () {
    test('formatPaise formats integer paise into INR', () {
      expect(CurrencyFormatter.formatPaise(42650), '₹426.50');
      expect(CurrencyFormatter.formatPaise(0), '₹0.00');
      expect(CurrencyFormatter.formatPaise(100), '₹1.00');
      expect(CurrencyFormatter.formatPaise(200000), '₹2,000.00');
    });

    test('formatWithStage distinguishes Estimated and Final', () {
      expect(
        CurrencyFormatter.formatWithStage(42650, isFinal: false),
        '₹426.50 (Estimated)',
      );
      expect(
        CurrencyFormatter.formatWithStage(42650, isFinal: true),
        '₹426.50 (Final)',
      );
    });
  });

  group('EstimatedShareFooter Widget Tests', () {
    testWidgets('renders Estimated label and running provisional share',
        (tester) async {
      var completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: EstimatedShareFooter(
              estimatedSharePaise: 42650,
              isCompleted: false,
              onDoneSelecting: () {
                completed = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('YOUR CURRENT ESTIMATED SHARE'), findsOneWidget);
      expect(find.text('Estimated'), findsOneWidget);
      expect(find.text('₹426.50'), findsOneWidget);
      expect(find.text('Done Selecting'), findsOneWidget);

      await tester.tap(find.text('Done Selecting'));
      await tester.pump();
      expect(completed, isTrue);
    });

    testWidgets('renders Selection Completed when frozen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: EstimatedShareFooter(
              estimatedSharePaise: 42650,
              isCompleted: true,
              onDoneSelecting: () {},
            ),
          ),
        ),
      );

      expect(find.text('Selection Completed'), findsOneWidget);
      expect(find.text('Done Selecting'), findsNothing);
      expect(
        find.text(
          'Your selections are locked. Share updates live as others finish.',
        ),
        findsOneWidget,
      );
    });
  });

  group('BillItemTile Widget Tests', () {
    testWidgets('renders item details and triggers onToggleClaim',
        (tester) async {
      var toggled = false;
      const item = BillItemModel(
        id: 'item-1',
        sessionId: 'sess-1',
        position: 0,
        name: 'Butter Chicken',
        pricePaise: 45000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BillItemTile(
              item: item,
              isClaimedByMe: false,
              claimants: const [],
              onToggleClaim: () {
                toggled = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Butter Chicken'), findsOneWidget);
      expect(find.text('₹450.00'), findsOneWidget);

      await tester.tap(find.byType(InkWell));
      await tester.pump();
      expect(toggled, isTrue);
    });

    testWidgets('renders shared claimants when multiple participants claim',
        (tester) async {
      const item = BillItemModel(
        id: 'item-2',
        sessionId: 'sess-1',
        position: 1,
        name: 'Large Pizza',
        pricePaise: 60000,
      );
      final claimants = [
        const ParticipantModel(
          id: 'p-1',
          sessionId: 'sess-1',
          userId: 'u-1',
          role: ParticipantRole.host,
          displayName: 'Alice',
        ),
        const ParticipantModel(
          id: 'p-2',
          sessionId: 'sess-1',
          userId: 'u-2',
          role: ParticipantRole.participant,
          displayName: 'Bob',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BillItemTile(
              item: item,
              isClaimedByMe: true,
              claimants: claimants,
              onToggleClaim: () {},
            ),
          ),
        ),
      );

      expect(
        find.text('Shared by 2 participants (~₹300.00 each)'),
        findsOneWidget,
      );
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });
  });

  group('ParticipantStatusRow Widget Tests', () {
    testWidgets('renders independent participant states accurately',
        (tester) async {
      final participant = ParticipantModel(
        id: 'p-1',
        sessionId: 'sess-1',
        userId: 'u-1',
        role: ParticipantRole.participant,
        displayName: 'Charlie',
        selectionCompletedAt: DateTime.now(),
      );
      const settlement = SettlementModel(
        participantId: 'p-1',
        sessionId: 'sess-1',
        finalAmountPaise: 35000,
        payPreference: PayPreference.selfPay,
        payStatus: PayStatus.pending,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParticipantStatusRow(
              participant: participant,
              settlement: settlement,
              hasClaims: true,
              isCurrentUser: true,
            ),
          ),
        ),
      );

      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text(' (You)'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Pending Confirmation'), findsOneWidget);
    });
  });
}
