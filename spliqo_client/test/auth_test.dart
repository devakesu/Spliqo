import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spliqo/core/storage/secure_storage_service.dart';
import 'package:spliqo/core/validation/auth_validators.dart';
import 'package:spliqo/data/datasources/api_client.dart';
import 'package:spliqo/data/repositories/auth_repository.dart';
import 'package:spliqo/state/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'secure_storage_test.dart';

class FakeGoogleAuthClient implements GoogleAuthClient {
  ({String idToken, String? accessToken, String? displayName})? nextResult;
  Exception? nextError;
  bool signedOut = false;

  @override
  Future<({String idToken, String? accessToken, String? displayName})?>
      signIn() async {
    if (nextError != null) {
      throw nextError!;
    }
    return nextResult;
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
  }
}

class FakeAuthRepository extends AuthRepository {
  new({
    required super.supabase,
    required super.apiClient,
    super.googleAuthClient,
  });

  bool googleCalled = false;
  bool signedOut = false;
  String? lastEmail;
  String? lastDisplayName;
  String? lastPhone;
  OtpType? lastOtpType;
  String? lastOtpToken;

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    lastEmail = email;
    return AuthResponse(
      session: _buildSession(userId: 'user-pw-1', email: email),
      user: _buildUser(userId: 'user-pw-1', email: email),
    );
  }

  @override
  Future<AuthResponse> signUpWithEmail({
    required String displayName,
    required String email,
    required String password,
  }) async {
    lastDisplayName = displayName;
    lastEmail = email;
    // Simulate email confirmation required (no session until OTP verified)
    return AuthResponse(
      user: _buildUser(userId: 'user-new-1', email: email),
    );
  }

  @override
  Future<UserResponse> requestPhoneVerification({required String phone}) async {
    lastPhone = phone;
    return UserResponse.fromJson({'id': 'user-new-1', 'phone': phone});
  }

  @override
  Future<AuthResponse> verifyOtp({
    required OtpType type,
    required String token,
    String? email,
    String? phone,
  }) async {
    lastOtpType = type;
    lastOtpToken = token;
    return AuthResponse(
      session: _buildSession(
        userId: 'user-new-1',
        email: email ?? 'priya@spliqo.app',
        phone: phone,
        emailConfirmed: true,
        phoneConfirmed: phone != null,
      ),
      user: _buildUser(
        userId: 'user-new-1',
        email: email ?? 'priya@spliqo.app',
        phone: phone,
        emailConfirmed: true,
        phoneConfirmed: phone != null,
      ),
    );
  }

  @override
  Future<AuthResponse> signInWithGoogle() async {
    googleCalled = true;
    return AuthResponse(
      session: _buildSession(
        userId: 'user-google-1',
        email: 'google@spliqo.app',
        displayName: 'Google Diner',
        emailConfirmed: true,
      ),
      user: _buildUser(
        userId: 'user-google-1',
        email: 'google@spliqo.app',
        displayName: 'Google Diner',
        emailConfirmed: true,
      ),
    );
  }

  @override
  Future<Map<String, dynamic>?> syncUserProfile({
    required String displayName,
    String? phoneNumber,
  }) async {
    return {
      'id': 'user-new-1',
      'display_name': displayName,
      'has_phone_number': phoneNumber != null,
      'masked_phone_number': phoneNumber != null ? '+91••••••3210' : null,
    };
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
  }

  static User _buildUser({
    required String userId,
    required String email,
    String? phone,
    String? displayName,
    bool emailConfirmed = false,
    bool phoneConfirmed = false,
  }) {
    return User(
      id: userId,
      appMetadata: const {'provider': 'email'},
      userMetadata: displayName != null ? {'display_name': displayName} : const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
      email: email,
      phone: phone ?? '',
      emailConfirmedAt: emailConfirmed ? '2026-01-01T00:00:00Z' : null,
      phoneConfirmedAt: phoneConfirmed ? '2026-01-01T00:00:00Z' : null,
    );
  }

  static Session _buildSession({
    required String userId,
    required String email,
    String? phone,
    String? displayName,
    bool emailConfirmed = false,
    bool phoneConfirmed = false,
  }) {
    return Session(
      accessToken: 'jwt-access-token-$userId',
      tokenType: 'bearer',
      user: _buildUser(
        userId: userId,
        email: email,
        phone: phone,
        displayName: displayName,
        emailConfirmed: emailConfirmed,
        phoneConfirmed: phoneConfirmed,
      ),
    );
  }
}

void main() {
  group('AuthValidators Tests', () {
    test('enforces strict 10+ char mixed password requirements', () {
      expect(AuthValidators.validatePassword('short1!A'), isNotNull);
      expect(AuthValidators.validatePassword('alllowercase1!'), isNotNull);
      expect(AuthValidators.validatePassword('NoDigitsHere!'), isNotNull);
      expect(AuthValidators.validatePassword('NoSymbolsHere12'), isNotNull);
      expect(AuthValidators.validatePassword('Spliqo@2026!'), isNull);
    });

    test('normalizes 10-digit Indian phone numbers to E.164', () {
      expect(
        AuthValidators.normalizePhoneE164('98765 43210'),
        equals('+919876543210'),
      );
      expect(AuthValidators.validatePhone('9876543210'), isNull);
      expect(AuthValidators.validatePhone('12345'), isNotNull);
    });
  });

  group('AuthNotifier & Identity State Tests', () {
    late FakeFlutterSecureStorage fakeStorage;
    late SecureStorageService secureStorageService;
    late FakeAuthRepository fakeRepo;

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      secureStorageService = SecureStorageService(storage: fakeStorage);
      fakeRepo = FakeAuthRepository(
        supabase: SupabaseClient('https://placeholder.supabase.co', 'key'),
        apiClient: ApiClient(),
      );
    });

    test('remains unauthenticated on cold start when no session exists',
        () async {
      final container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider
              .overrideWithValue(secureStorageService),
          authRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.initAuth();

      final authState = container.read(authNotifierProvider);
      expect(authState.isAuthenticated, isFalse);
      expect(authState.user, isNull);
    });

    test('purges legacy dev-local-offline-token on init', () async {
      await secureStorageService.saveUserId('legacy-id');
      await secureStorageService.saveAuthToken('dev-local-offline-token');

      final container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider
              .overrideWithValue(secureStorageService),
          authRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.initAuth();

      final authState = container.read(authNotifierProvider);
      expect(authState.isAuthenticated, isFalse);
      expect(await secureStorageService.getAuthToken(), isNull);
    });

    test('handles signup -> email OTP -> phone OTP two-step verification',
        () async {
      final container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider
              .overrideWithValue(secureStorageService),
          authRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.initAuth();

      final started = await notifier.signUpWithEmail(
        displayName: 'Priya',
        email: 'priya@spliqo.app',
        password: 'Spliqo@2026!',
        phone: '9876543210',
      );
      expect(started, isTrue);

      var state = container.read(authNotifierProvider);
      expect(state.pendingOtp?.kind, equals(OtpFlowKind.signupEmail));
      expect(
        state.pendingOtp?.pendingPhoneAfterEmail,
        equals('+919876543210'),
      );

      // Step 1: verify email OTP -> advances to phone OTP
      final step1 = await notifier.verifyPendingOtp(token: '123456');
      expect(step1, equals('next_phone'));
      expect(fakeRepo.lastOtpType, equals(OtpType.signup));
      expect(fakeRepo.lastPhone, equals('+919876543210'));

      state = container.read(authNotifierProvider);
      expect(state.pendingOtp?.kind, equals(OtpFlowKind.signupPhone));

      // Step 2: verify phone OTP -> completes
      final step2 = await notifier.verifyPendingOtp(token: '654321');
      expect(step2, equals('done'));
      expect(fakeRepo.lastOtpType, equals(OtpType.phoneChange));

      state = container.read(authNotifierProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.user?.displayName, equals('Priya'));
      expect(state.user?.maskedPhone, equals('+91••••••3210'));
    });

    test('signs in with Google and clears state on signOut', () async {
      final container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider
              .overrideWithValue(secureStorageService),
          authRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(authNotifierProvider.notifier);
      await notifier.initAuth();

      final ok = await notifier.signInWithGoogle();
      expect(ok, isTrue);
      expect(fakeRepo.googleCalled, isTrue);

      var state = container.read(authNotifierProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.user?.displayName, equals('Google Diner'));

      await notifier.signOut();
      state = container.read(authNotifierProvider);
      expect(state.isAuthenticated, isFalse);
      expect(state.user, isNull);
      expect(fakeRepo.signedOut, isTrue);
      expect(await secureStorageService.getAuthToken(), isNull);
    });
  });
}
