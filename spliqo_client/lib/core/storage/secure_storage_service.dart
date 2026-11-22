import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:spliqo/core/errors/failures.dart';

/// Failure thrown whenever secure hardware-backed storage operations fail.
/// Fails closed: NO unencrypted or plaintext fallback is permitted.
class SecureStorageFailure extends Failure {
  const new({
    required super.message,
    super.code = 'secure_storage_error',
    super.fields = const <Map<String, String>>[],
  });
}

/// Known storage keys for sensitive credentials.
abstract final class SecureStorageKeys {
  static const String authToken = 'spliqo_sec_auth_token';
  static const String refreshToken = 'spliqo_sec_refresh_token';
  static const String userId = 'spliqo_sec_user_id';
  static const String userDisplayName = 'spliqo_sec_user_display_name';
  static const String hostPayoutUpi = 'spliqo_sec_host_payout_upi';
}

/// Enterprise-grade secure storage service enforcing hardware-backed encryption.
///
/// Strictly enforces:
/// - Android: Hardware KeyStore RSA OAEP + AES GCM encryption (v11 default).
/// - iOS: Keychain with FirstUnlockThisDeviceOnly.
/// - Fail-closed: Never falls back to unencrypted SharedPreferences or plaintext.
class SecureStorageService {
  new({
    FlutterSecureStorage? storage,
  }) : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: false, // Strict: Never reset or wipe silently on error
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  /// Writes a key-value pair strictly to encrypted storage.
  Future<void> write({
    required String key,
    required String value,
  }) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      throw SecureStorageFailure(
        message: 'Failed to write securely to KeyStore/Keychain: $e',
        fields: [
          {'key': key},
        ],
      );
    }
  }

  /// Reads a decrypted value for the specified key.
  Future<String?> read({required String key}) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      throw SecureStorageFailure(
        message: 'Failed to read securely from KeyStore/Keychain: $e',
        fields: [
          {'key': key},
        ],
      );
    }
  }

  /// Deletes a key from encrypted storage.
  Future<void> delete({required String key}) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      throw SecureStorageFailure(
        message: 'Failed to delete securely from KeyStore/Keychain: $e',
        fields: [
          {'key': key},
        ],
      );
    }
  }

  /// Checks if a key exists in encrypted storage.
  Future<bool> containsKey({required String key}) async {
    try {
      return await _storage.containsKey(key: key);
    } catch (e) {
      throw SecureStorageFailure(
        message: 'Failed to verify key existence in KeyStore/Keychain: $e',
        fields: [
          {'key': key},
        ],
      );
    }
  }

  /// Wipes all sensitive credentials upon explicit logout.
  Future<void> clearAll() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      throw SecureStorageFailure(
        message: 'Failed to wipe secure storage: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Strongly-typed accessors for Spliqo core credentials
  // ---------------------------------------------------------------------------

  Future<void> saveAuthToken(String token) =>
      write(key: SecureStorageKeys.authToken, value: token);

  Future<String?> getAuthToken() => read(key: SecureStorageKeys.authToken);

  Future<void> deleteAuthToken() => delete(key: SecureStorageKeys.authToken);

  Future<void> saveUserId(String userId) =>
      write(key: SecureStorageKeys.userId, value: userId);

  Future<String?> getUserId() => read(key: SecureStorageKeys.userId);

  Future<void> saveUserDisplayName(String name) =>
      write(key: SecureStorageKeys.userDisplayName, value: name);

  Future<String?> getUserDisplayName() =>
      read(key: SecureStorageKeys.userDisplayName);

  Future<void> saveHostPayoutUpi(String upiId) =>
      write(key: SecureStorageKeys.hostPayoutUpi, value: upiId);

  Future<String?> getHostPayoutUpi() =>
      read(key: SecureStorageKeys.hostPayoutUpi);

  Future<void> deleteHostPayoutUpi() =>
      delete(key: SecureStorageKeys.hostPayoutUpi);
}

/// Global provider for [SecureStorageService].
final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});
