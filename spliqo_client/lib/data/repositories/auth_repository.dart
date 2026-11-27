import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:spliqo/core/config/app_config.dart';
import 'package:spliqo/core/constants/app_strings.dart';
import 'package:spliqo/core/errors/failures.dart';
import 'package:spliqo/data/datasources/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Exception raised when a user cancels an interactive OAuth flow cleanly.
class AuthCanceledException implements Exception {
  const new();
}

/// Abstracts native Google Sign-In so authentication flows can be unit-tested.
abstract class GoogleAuthClient {
  Future<({String idToken, String? accessToken, String? displayName})?>
      signIn();
  Future<void> signOut();
}

/// Native Google Sign-In v7 implementation using [GoogleSignIn.instance].
class NativeGoogleAuthClient implements GoogleAuthClient {
  new({
    String? webClientId,
    String? iosClientId,
  })  : _webClientId = webClientId ?? AppConfig.current.googleWebClientId,
        _iosClientId = iosClientId ?? AppConfig.current.googleIosClientId;

  final String _webClientId;
  final String _iosClientId;
  Future<void>? _initFuture;

  Future<void> _ensureInitialized() {
    return _initFuture ??= _performInit();
  }

  Future<void> _performInit() async {
    final hasWebId =
        _webClientId.isNotEmpty && !_webClientId.contains('YOUR_WEB_CLIENT_ID');
    final hasIosId =
        _iosClientId.isNotEmpty && !_iosClientId.contains('YOUR_IOS_CLIENT_ID');

    if (!hasWebId && !hasIosId && !kIsWeb) {
      throw const Failure(
        code: 'google_not_configured',
        message:
            'Google Sign-In is not configured yet. Add GOOGLE_WEB_CLIENT_ID and GOOGLE_IOS_CLIENT_ID.',
      );
    }

    await GoogleSignIn.instance.initialize(
      clientId: hasIosId ? _iosClientId : null,
      serverClientId: hasWebId ? _webClientId : null,
    );
  }

  @override
  Future<({String idToken, String? accessToken, String? displayName})?>
      signIn() async {
    await _ensureInitialized();

    final signIn = GoogleSignIn.instance;
    if (!signIn.supportsAuthenticate()) {
      throw const Failure(
        code: 'google_unsupported',
        message: 'Native Google Sign-In is not supported on this platform.',
      );
    }

    try {
      final account = await signIn.authenticate(
        scopeHint: const ['email', 'profile'],
      );
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const Failure(
          code: 'google_missing_id_token',
          message: 'Google sign-in did not return an identity token.',
        );
      }

      final authorization = await account.authorizationClient
          .authorizationForScopes(const ['email', 'profile']);

      return (
        idToken: idToken,
        accessToken: authorization?.accessToken,
        displayName: account.displayName,
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthCanceledException();
      }
      throw Failure(
        code: 'google_sign_in_failed',
        message: e.description ?? 'Google Sign-In failed.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    if (_initFuture == null) {
      return;
    }
    try {
      await GoogleSignIn.instance.signOut();
    } on Object catch (_) {
      // Ignore Google sign-out errors during cleanup.
    }
  }
}

/// Repository encapsulating all Supabase Auth, OTP, Google OAuth, and Backend profile sync calls.
class AuthRepository {
  new({
    required this.supabase,
    required this.apiClient,
    GoogleAuthClient? googleAuthClient,
  }) : _googleAuthClient = googleAuthClient ?? NativeGoogleAuthClient();

  final SupabaseClient supabase;
  final ApiClient apiClient;
  final GoogleAuthClient _googleAuthClient;

  Stream<AuthState> get onAuthStateChange => supabase.auth.onAuthStateChange;

  Session? get currentSession => supabase.auth.currentSession;

  User? get currentUser => supabase.auth.currentUser;

  /// Email + Password sign in.
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      return await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on AuthException catch (e) {
      throw _mapAuthException(e, isSignIn: true);
    }
  }

  /// Email + Password sign up with profile metadata (`display_name`).
  Future<AuthResponse> signUpWithEmail({
    required String displayName,
    required String email,
    required String password,
  }) async {
    try {
      return await supabase.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
        emailRedirectTo: 'devakesu-spliqo://login-callback',
      );
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    }
  }

  /// Sends a passwordless 6-digit Email OTP.
  Future<void> sendEmailOtp({
    required String email,
    bool shouldCreateUser = false,
  }) async {
    try {
      await supabase.auth.signInWithOtp(
        email: email,
        shouldCreateUser: shouldCreateUser,
        emailRedirectTo: 'devakesu-spliqo://login-callback',
      );
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    }
  }

  /// Sends a passwordless 6-digit Phone SMS OTP.
  Future<void> sendPhoneOtp({
    required String phone,
    bool shouldCreateUser = false,
  }) async {
    try {
      await supabase.auth.signInWithOtp(
        phone: phone,
        shouldCreateUser: shouldCreateUser,
      );
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    }
  }

  /// Resends signup / emailChange / phoneChange OTP.
  Future<void> resendOtp({
    required OtpType type,
    String? email,
    String? phone,
  }) async {
    try {
      await supabase.auth.resend(
        type: type,
        email: email,
        phone: phone,
      );
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    }
  }

  /// Requests SMS OTP verification to bind a phone number to the signed-in user.
  Future<UserResponse> requestPhoneVerification({required String phone}) async {
    try {
      return await supabase.auth.updateUser(
        UserAttributes(phone: phone),
      );
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    }
  }

  /// Verifies an Email or Phone OTP token.
  Future<AuthResponse> verifyOtp({
    required OtpType type,
    required String token,
    String? email,
    String? phone,
  }) async {
    try {
      return await supabase.auth.verifyOTP(
        type: type,
        token: token,
        email: email,
        phone: phone,
      );
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    }
  }

  /// Sends a password recovery OTP/email.
  Future<void> sendPasswordResetOtp({required String email}) async {
    try {
      await supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'devakesu-spliqo://login-callback',
      );
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    }
  }

  /// Completes password reset or password update for an authenticated user.
  Future<UserResponse> updatePassword({required String newPassword}) async {
    try {
      return await supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    }
  }

  /// Native Google Sign-In exchanged with Supabase via `signInWithIdToken`.
  Future<AuthResponse> signInWithGoogle() async {
    final googleResult = await _googleAuthClient.signIn();
    if (googleResult == null) {
      throw const AuthCanceledException();
    }

    try {
      return await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: googleResult.idToken,
        accessToken: googleResult.accessToken,
      );
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    }
  }

  /// Syncs display_name and optional E.164 phone number to FastAPI (FLE encrypted).
  Future<Map<String, dynamic>?> syncUserProfile({
    required String displayName,
    String? phoneNumber,
  }) async {
    try {
      return await apiClient.put(
        '/users/me/profile',
        body: {
          'display_name': displayName,
          if (phoneNumber != null && phoneNumber.isNotEmpty)
            'phone_number': phoneNumber,
        },
      );
    } on Failure {
      rethrow;
    } on Object catch (_) {
      return null;
    }
  }

  /// Fetches masked profile from FastAPI.
  Future<Map<String, dynamic>?> fetchUserProfile() async {
    try {
      return await apiClient.get('/users/me/profile');
    } on Object catch (_) {
      return null;
    }
  }

  /// Signs out from Supabase and native Google Sign-In.
  Future<void> signOut() async {
    await Future.wait([
      _googleAuthClient.signOut(),
      supabase.auth.signOut(),
    ]);
  }

  Failure _mapAuthException(AuthException e, {bool isSignIn = false}) {
    final status = e.statusCode ?? '';
    final msg = e.message.toLowerCase();

    if (status == '429' ||
        msg.contains('rate limit') ||
        msg.contains('too many requests') ||
        msg.contains('security purposes')) {
      return const Failure(
        code: 'rate_limited',
        message: AppStrings.rateLimitNotice,
      );
    }

    if (isSignIn && msg.contains('invalid login credentials')) {
      // Uniform response to prevent account enumeration (Standards 5.5)
      return const Failure(
        code: 'invalid_credentials',
        message: 'Invalid email or password.',
      );
    }

    if (msg.contains('email not confirmed')) {
      return const Failure(
        code: 'email_not_confirmed',
        message: 'Please verify your email with the 6-digit code first.',
      );
    }

    if (msg.contains('expired') || msg.contains('token has expired')) {
      return const Failure(
        code: 'otp_expired',
        message: 'That verification code has expired. Request a new code.',
      );
    }

    if (msg.contains('invalid') && msg.contains('otp')) {
      return const Failure(
        code: 'invalid_otp',
        message: 'Invalid verification code. Please check and try again.',
      );
    }

    if (msg.contains('weak_password') || msg.contains('password')) {
      return Failure(
        code: 'weak_password',
        message: e.message,
      );
    }

    return Failure(
      code: e.code ?? 'auth_error',
      message: e.message,
    );
  }
}
