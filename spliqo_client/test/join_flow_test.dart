import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spliqo/core/constants/app_strings.dart';
import 'package:spliqo/core/storage/secure_storage_service.dart';
import 'package:spliqo/data/datasources/api_client.dart';
import 'package:spliqo/presentation/screens/join_screen.dart';
import 'package:spliqo/presentation/widgets/join_room_sheet.dart';
import 'package:spliqo/presentation/widgets/name_prompt_sheet.dart';
import 'package:spliqo/state/session_providers.dart';

import 'secure_storage_test.dart';

class FakeApiClient implements ApiClient {
  String? lastPath;
  Map<String, dynamic>? lastBody;
  Map<String, dynamic> response = {
    'id': 'part-123',
    'session_id': 'sess-joined-456',
    'user_id': 'user-123',
    'role': 'participant',
    'display_name': 'Guest User',
  };

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    lastPath = path;
    lastBody = body;
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSessionRoomNotifier extends SessionRoomNotifier {
  new(super.sessionId);

  @override
  SessionRoomState build() => const SessionRoomState();
}

void main() {
  group('Join Flow & Deep Linking Widget Tests', () {
    late FakeFlutterSecureStorage fakeStorage;
    late SecureStorageService secureStorageService;
    late FakeApiClient fakeApiClient;

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      secureStorageService = SecureStorageService(storage: fakeStorage);
      fakeApiClient = FakeApiClient();
    });

    testWidgets('JoinScreen renders deep link invitation view when token provided',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageServiceProvider
                .overrideWithValue(secureStorageService),
            apiClientProvider.overrideWithValue(fakeApiClient),
            sessionRoomProvider('sess-joined-456').overrideWith(
              () => FakeSessionRoomNotifier('sess-joined-456'),
            ),
          ],
          child: const MaterialApp(
            home: JoinScreen(initialToken: 'SPL7X2'),
          ),
        ),
      );

      // Verify deep-link title & invitation card
      expect(find.text("You're Invited to Dinner!"), findsOneWidget);
      expect(find.text('Room Code: SPL7X2'), findsOneWidget);
      expect(find.text('Accept & Join Table'), findsOneWidget);

      // Enter name
      await tester.enterText(
        find.widgetWithText(TextField, 'e.g. Alex'),
        'Priya Guest',
      );

      // Tap Accept & Join
      await tester.tap(find.text('Accept & Join Table'));
      await tester.pump();

      // Verify API was called with token and name
      expect(fakeApiClient.lastPath, equals('/sessions/join'));
      expect(fakeApiClient.lastBody?['invite_token'], equals('SPL7X2'));
      expect(fakeApiClient.lastBody?['display_name'], equals('Priya Guest'));

      // Verify name saved in KeyStore
      final savedName = await secureStorageService.getUserDisplayName();
      expect(savedName, equals('Priya Guest'));
    });

    testWidgets('JoinScreen standard mode validates empty code and name',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageServiceProvider
                .overrideWithValue(secureStorageService),
            apiClientProvider.overrideWithValue(fakeApiClient),
            sessionRoomProvider('sess-joined-456').overrideWith(
              () => FakeSessionRoomNotifier('sess-joined-456'),
            ),
          ],
          child: const MaterialApp(
            home: JoinScreen(),
          ),
        ),
      );

      expect(find.text(AppStrings.joinTitle), findsOneWidget);
      expect(find.text('Join Dinner Table'), findsOneWidget);

      // Tap join with empty fields
      await tester.tap(find.text(AppStrings.joinRoomCTA));
      await tester.pump();

      // Error banner displayed
      expect(
        find.text('Please enter a valid room code.'),
        findsOneWidget,
      );
    });

    testWidgets('JoinRoomSheet prompts and submits join payload',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageServiceProvider
                .overrideWithValue(secureStorageService),
            apiClientProvider.overrideWithValue(fakeApiClient),
            sessionRoomProvider('sess-joined-456').overrideWith(
              () => FakeSessionRoomNotifier('sess-joined-456'),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: JoinRoomSheet(initialToken: 'ROOM99'),
            ),
          ),
        ),
      );

      expect(find.text('Join Dinner Split'), findsOneWidget);
      expect(find.text('ROOM99'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Your name at table'),
        'Alex Dining',
      );

      await tester.tap(find.text('Join Room'));
      await tester.pump();

      expect(fakeApiClient.lastPath, equals('/sessions/join'));
      expect(fakeApiClient.lastBody?['invite_token'], equals('ROOM99'));
      expect(fakeApiClient.lastBody?['display_name'], equals('Alex Dining'));
    });

    testWidgets('NamePromptSheet saves user display name', (tester) async {
      String? returnedName;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageServiceProvider
                .overrideWithValue(secureStorageService),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () async {
                      returnedName = await NamePromptSheet.show(context);
                    },
                    child: const Text('Open Prompt'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Prompt'));
      await tester.pumpAndSettle();

      expect(find.text('What should we call you?'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField),
        'Kavya',
      );

      await tester.tap(find.text('Continue to Table'));
      await tester.pumpAndSettle();

      expect(returnedName, equals('Kavya'));
      expect(
        await secureStorageService.getUserDisplayName(),
        equals('Kavya'),
      );
    });
  });
}
