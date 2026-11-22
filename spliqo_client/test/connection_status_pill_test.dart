import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spliqo/presentation/widgets/connection_status_pill.dart';

void main() {
  group('ConnectionStatusPill Widget Tests', () {
    testWidgets('renders Live Sync indicator when live', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConnectionStatusPill(),
          ),
        ),
      );

      expect(find.text('Live Sync'), findsOneWidget);
    });

    testWidgets('renders Reconnecting indicator when reconnecting',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConnectionStatusPill(
              status: RealtimeConnectionStatus.reconnecting,
            ),
          ),
        ),
      );

      expect(find.text('Reconnecting...'), findsOneWidget);
    });

    testWidgets('renders Offline indicator and triggers retry on tap',
        (tester) async {
      var retryTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConnectionStatusPill(
              status: RealtimeConnectionStatus.offline,
              onRetry: () => retryTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Offline'), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

      await tester.tap(find.text('Offline'));
      await tester.pump();

      expect(retryTapped, isTrue);
    });
  });
}
