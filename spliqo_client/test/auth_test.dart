import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spliqo/core/storage/secure_storage_service.dart';
import 'package:spliqo/state/auth_provider.dart';

import 'secure_storage_test.dart';

void main() {
  group('AuthNotifier & Identity State Tests', () {
    late FakeFlutterSecureStorage fakeStorage;
    late SecureStorageService secureStorageService;

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      secureStorageService = SecureStorageService(storage: fakeStorage);
    });

    test('initializes with stored user identity and tokens from KeyStore',
        () async {
      await secureStorageService.saveUserId('user-uuid-123');
      await secureStorageService.saveUserDisplayName('Priya');
      await secureStorageService.saveAuthToken('bearer-jwt-token');

      final container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider
              .overrideWithValue(secureStorageService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.initAuth();

      // Read auth state
      final authState = container.read(authNotifierProvider);

      // Verify restored identity
      expect(authState.user?.id, equals('user-uuid-123'));
      expect(authState.user?.displayName, equals('Priya'));
      expect(authState.authToken, equals('bearer-jwt-token'));
      expect(authState.isAuthenticated, isTrue);
      expect(authState.hasDisplayName, isTrue);
    });

    test('updateDisplayName persists strictly to KeyStore and updates state',
        () async {
      final container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider
              .overrideWithValue(secureStorageService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.initAuth();
      await notifier.updateDisplayName('Sammy');

      final state = container.read(authNotifierProvider);
      expect(state.user?.displayName, equals('Sammy'));

      // Verify persisted in KeyStore
      final savedName = await secureStorageService.getUserDisplayName();
      expect(savedName, equals('Sammy'));
    });

    test('signOut wipes credentials from KeyStore and clears state', () async {
      await secureStorageService.saveAuthToken('token-abc');
      await secureStorageService.saveUserId('uid-abc');
      await secureStorageService.saveUserDisplayName('Alice');

      final container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider
              .overrideWithValue(secureStorageService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.initAuth();
      await notifier.signOut();

      final state = container.read(authNotifierProvider);
      expect(state.isAuthenticated, isFalse);
      expect(state.user, isNull);

      expect(await secureStorageService.getAuthToken(), isNull);
      expect(await secureStorageService.getUserId(), isNull);
    });
  });
}
