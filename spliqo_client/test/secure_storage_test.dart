import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spliqo/core/storage/secure_storage_service.dart';

class FakeFlutterSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};
  bool shouldThrow = false;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) {
      throw Exception('KeyStore unavailable');
    }
    if (value != null) {
      _data[key] = value;
    } else {
      _data.remove(key);
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) {
      throw Exception('Keychain access error');
    }
    return _data[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) {
      throw Exception('KeyStore delete failure');
    }
    _data.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) {
      throw Exception('KeyStore query failure');
    }
    return _data.containsKey(key);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    if (shouldThrow) {
      throw Exception('KeyStore wipe failure');
    }
    _data.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SecureStorageService Strict Storage Tests', () {
    late FakeFlutterSecureStorage fakeStorage;
    late SecureStorageService service;

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      service = SecureStorageService(storage: fakeStorage);
    });

    test('writes and reads auth token securely', () async {
      await service.saveAuthToken('secret-jwt-token');
      final retrieved = await service.getAuthToken();
      expect(retrieved, equals('secret-jwt-token'));
    });

    test('writes and reads host payout UPI ID securely', () async {
      await service.saveHostPayoutUpi('host@okhdfcbank');
      final retrieved = await service.getHostPayoutUpi();
      expect(retrieved, equals('host@okhdfcbank'));

      await service.deleteHostPayoutUpi();
      final afterDelete = await service.getHostPayoutUpi();
      expect(afterDelete, isNull);
    });

    test('fails closed when KeyStore hardware fails (strict no fallback)',
        () async {
      fakeStorage.shouldThrow = true;

      expect(
        () => service.saveAuthToken('token-123'),
        throwsA(isA<SecureStorageFailure>()),
      );

      expect(
        () => service.getAuthToken(),
        throwsA(isA<SecureStorageFailure>()),
      );
    });

    test('clearAll wipes all credentials', () async {
      await service.saveAuthToken('token-1');
      await service.saveUserId('user-1');
      await service.saveHostPayoutUpi('host@upi');

      await service.clearAll();

      expect(await service.getAuthToken(), isNull);
      expect(await service.getUserId(), isNull);
      expect(await service.getHostPayoutUpi(), isNull);
    });
  });
}
