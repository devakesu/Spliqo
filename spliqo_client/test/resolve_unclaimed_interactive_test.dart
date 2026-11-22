import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spliqo/domain/models/session.dart';
import 'package:spliqo/presentation/widgets/resolve_unclaimed_sheet.dart';

void main() {
  const items = [
    BillItemModel(
      id: 'i-1',
      sessionId: 'sess-1',
      name: 'Garlic Bread',
      pricePaise: 20000,
      position: 0,
    ),
    BillItemModel(
      id: 'i-2',
      sessionId: 'sess-1',
      name: 'Cold Drink',
      pricePaise: 10000,
      position: 1,
    ),
  ];

  const participants = [
    ParticipantModel(
      id: 'p-1',
      sessionId: 'sess-1',
      userId: 'u-1',
      displayName: 'Alice Host',
      role: ParticipantRole.host,
    ),
    ParticipantModel(
      id: 'p-2',
      sessionId: 'sess-1',
      userId: 'u-2',
      displayName: 'Bob Guest',
      role: ParticipantRole.participant,
    ),
  ];

  group('ResolveUnclaimedSheet Interactive Tests', () {
    testWidgets(
        'renders unclaimed items checklist with initial full selection and splits among all',
        (tester) async {
      String? resolvedAction;
      List<String>? resolvedItemIds;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResolveUnclaimedSheet(
              unclaimedItems: items,
              participants: participants,
              onResolve: ({
                required action,
                targetParticipantId,
                itemIds,
              }) async {
                resolvedAction = action;
                resolvedItemIds = itemIds;
              },
            ),
          ),
        ),
      );

      // Verify header and item checklist
      expect(find.text('Unresolved Items (2)'), findsOneWidget);
      expect(find.text('Selected: 2 items (₹300.00)'), findsOneWidget);
      expect(find.text('Garlic Bread'), findsOneWidget);
      expect(find.text('Cold Drink'), findsOneWidget);
      expect(find.text('Deselect All'), findsOneWidget);

      // Tap "Split Among All Participants"
      await tester.tap(find.text('Split Among All Participants'));
      await tester.pumpAndSettle();

      expect(resolvedAction, 'split_all');
      expect(resolvedItemIds, ['i-1', 'i-2']);
    });

    testWidgets('allows cherry-picking items and resolving with host absorb',
        (tester) async {
      String? resolvedAction;
      List<String>? resolvedItemIds;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResolveUnclaimedSheet(
              unclaimedItems: items,
              participants: participants,
              onResolve: ({
                required action,
                targetParticipantId,
                itemIds,
              }) async {
                resolvedAction = action;
                resolvedItemIds = itemIds;
              },
            ),
          ),
        ),
      );

      // Deselect all
      await tester.tap(find.text('Deselect All'));
      await tester.pumpAndSettle();
      expect(find.text('Selected: 0 items (₹0.00)'), findsOneWidget);

      // Select only "Garlic Bread"
      await tester.tap(find.text('Garlic Bread'));
      await tester.pumpAndSettle();
      expect(find.text('Selected: 1 items (₹200.00)'), findsOneWidget);

      // Tap "Host Absorbs Unclaimed"
      await tester.tap(find.text('Host Absorbs Unclaimed'));
      await tester.pumpAndSettle();

      expect(resolvedAction, 'host_absorb');
      expect(resolvedItemIds, ['i-1']);
    });

    testWidgets('assigns items to a specific participant', (tester) async {
      String? resolvedAction;
      String? resolvedTargetParticipantId;
      List<String>? resolvedItemIds;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResolveUnclaimedSheet(
              unclaimedItems: items,
              participants: participants,
              onResolve: ({
                required action,
                targetParticipantId,
                itemIds,
              }) async {
                resolvedAction = action;
                resolvedTargetParticipantId = targetParticipantId;
                resolvedItemIds = itemIds;
              },
            ),
          ),
        ),
      );

      // Open dropdown and select Bob Guest (p-2)
      await tester.tap(find.text('Alice Host'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bob Guest').last);
      await tester.pumpAndSettle();

      // Tap confirm assignment
      await tester.tap(find.text('Confirm Assignment to Participant'));
      await tester.pumpAndSettle();

      expect(resolvedAction, 'assign_to_participant');
      expect(resolvedTargetParticipantId, 'p-2');
      expect(resolvedItemIds, ['i-1', 'i-2']);
    });
  });
}
