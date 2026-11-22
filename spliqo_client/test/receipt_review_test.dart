import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:spliqo/core/storage/secure_storage_service.dart';
import 'package:spliqo/domain/models/session.dart';
import 'package:spliqo/presentation/screens/receipt_review_screen.dart';
import 'package:spliqo/presentation/widgets/invite_share_sheet.dart';
import 'package:spliqo/presentation/widgets/receipt_preview_dialog.dart';
import 'package:spliqo/state/session_providers.dart';

import 'flow_test.dart';
import 'join_flow_test.dart';
import 'secure_storage_test.dart';

void main() {
  group('Phase 2: Receipt Review, Editor & Sharing Widget Tests', () {
    late FakeFlutterSecureStorage fakeStorage;
    late SecureStorageService secureStorageService;
    late FakeSessionRepository fakeRepo;
    late FakeApiClient fakeApiClient;

    const sampleSession = SessionModel(
      id: 'sess-draft-1',
      hostId: 'host-1',
      title: 'Copper Chimney',
      currency: 'INR',
      subtotalPaise: 100000, // ₹1,000.00
      taxPaise: 5000,        // ₹50.00
      serviceChargePaise: 0,
      discountPaise: 0,
      roundOffPaise: 0,
      totalPaise: 105000,    // ₹1,050.00
      status: SessionStatus.draft,
      revision: 0,
      items: [
        BillItemModel(
          id: 'item-1',
          sessionId: 'sess-draft-1',
          name: 'Butter Chicken',
          pricePaise: 60000,
          position: 0,
        ),
        BillItemModel(
          id: 'item-2',
          sessionId: 'sess-draft-1',
          name: 'Butter Naan',
          pricePaise: 40000,
          position: 1,
        ),
      ],
    );

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      secureStorageService = SecureStorageService(storage: fakeStorage);
      fakeRepo = FakeSessionRepository(session: sampleSession);
      fakeApiClient = FakeApiClient();
    });

    testWidgets('Empty state renders Camera, Gallery and Manual Fallback CTAs',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageServiceProvider
                .overrideWithValue(secureStorageService),
            sessionRepositoryProvider.overrideWithValue(fakeRepo),
            apiClientProvider.overrideWithValue(fakeApiClient),
          ],
          child: const MaterialApp(
            home: ReceiptReviewScreen(),
          ),
        ),
      );

      expect(find.text('Capture or Upload Receipt'), findsOneWidget);
      expect(find.text('Take Receipt Photo'), findsOneWidget);
      expect(find.text('Choose from Gallery'), findsOneWidget);
      expect(find.text('Enter Line Items Manually'), findsOneWidget);
    });

    testWidgets('Manual fallback button populates editable draft and balanced reconciliation',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageServiceProvider
                .overrideWithValue(secureStorageService),
            sessionRepositoryProvider.overrideWithValue(fakeRepo),
            apiClientProvider.overrideWithValue(fakeApiClient),
          ],
          child: const MaterialApp(
            home: ReceiptReviewScreen(),
          ),
        ),
      );

      await tester.tap(find.text('Enter Line Items Manually'));
      await tester.pumpAndSettle();

      expect(find.text('Dinner Table'), findsOneWidget);
      expect(find.text('Main Dish'), findsOneWidget);
      expect(find.text('₹500.00'), findsNWidgets(2));
      expect(
        find.text('Receipt balanced: All line items and adjustments match total exactly.'),
        findsOneWidget,
      );
    });

    testWidgets('Line items display and live reconciliation balances correctly',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageServiceProvider
                .overrideWithValue(secureStorageService),
            sessionRepositoryProvider.overrideWithValue(fakeRepo),
            apiClientProvider.overrideWithValue(fakeApiClient),
          ],
          child: const MaterialApp(
            home: ReceiptReviewScreen(initialSession: sampleSession),
          ),
        ),
      );

      expect(find.text('Copper Chimney'), findsOneWidget);
      expect(find.text('Butter Chicken'), findsOneWidget);
      expect(find.text('₹600.00'), findsOneWidget);
      expect(find.text('Butter Naan'), findsOneWidget);
      expect(find.text('₹400.00'), findsOneWidget);

      // Reconciled banner
      expect(
        find.text('Receipt balanced: All line items and adjustments match total exactly.'),
        findsOneWidget,
      );

      // Tap on Butter Chicken to open edit sheet
      await tester.tap(find.text('Butter Chicken'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Line Item'), findsOneWidget);
      expect(find.text('Split item into 2 parts'), findsOneWidget);

      // Tap Split button
      await tester.tap(find.text('Split'));
      await tester.pumpAndSettle();

      // Original ₹600.00 should be split into 2 parts of ₹300.00 each
      expect(find.text('Butter Chicken (Part 1/2)'), findsOneWidget);
      expect(find.text('Butter Chicken (Part 2/2)'), findsOneWidget);
      expect(find.text('₹300.00'), findsNWidgets(2));

      // Receipt is still balanced!
      expect(
        find.text('Receipt balanced: All line items and adjustments match total exactly.'),
        findsOneWidget,
      );
    });

    testWidgets('ReceiptPreviewDialog renders image with InteractiveViewer',
        (tester) async {
      final fakeBytes = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00,
        ...List.filled(20, 0),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReceiptPreviewDialog(
              imageBytes: fakeBytes,
              title: 'Paragon Receipt',
            ),
          ),
        ),
      );

      expect(find.text('Paragon Receipt'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('Pinch to zoom in on line items or taxes'), findsOneWidget);
    });

    testWidgets('InviteShareSheet renders room code, share options, and table QR code',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InviteShareSheet(
              sessionId: 'sess-abc-123',
              roomCode: 'SPL7X2',
              sessionTitle: 'Lunch at Toast & Tonic',
            ),
          ),
        ),
      );

      expect(find.text('Invite Your Dining Friends'), findsOneWidget);
      expect(find.text('Room Code: SPL7X2'), findsOneWidget);
      expect(find.text('Scan to join table'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Copy Link'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Enter Live Room'), findsOneWidget);
    });
  });
}
