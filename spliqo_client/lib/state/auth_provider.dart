import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spliqo/core/errors/failures.dart';
import 'package:spliqo/core/storage/secure_storage_service.dart';
import 'package:spliqo/core/validation/auth_validators.dart';
import 'package:spliqo/data/datasources/supabase_client_provider.dart';
import 'package:spliqo/data/repositories/auth_repository.dart';
import 'package:spliqo/state/session_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

/// Identifies which verification step the OTP flow is currently executing.
enum OtpFlowKind {
  signupEmail,
  signupPhone,
  loginEmail,
  loginPhone,
  linkPhone,
  passwordRecovery,
}

/// Captures context for an active multi-step or single-step OTP verification.
@immutable
class PendingOtpContext {
  const new({
    required this.kind,
    this.email,
    this.phone,
    this.displayName,
    this.pendingPhoneAfterEmail,
  });

  final OtpFlowKind kind;
  final String? email;
  final String? phone;
  final String? displayName;
  final String? pendingPhoneAfterEmail;

  bool get isPhoneStep =>
      kind == OtpFlowKind.signupPhone ||
      kind == OtpFlowKind.loginPhone ||
      kind == OtpFlowKind.linkPhone;

  PendingOtpContext copyWith({
    OtpFlowKind? kind,
    String? email,
    String? phone,
    String? displayName,
    String? pendingPhoneAfterEmail,
  }) {
    return PendingOtpContext(
      kind: kind ?? this.kind,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      displayName: displayName ?? this.displayName,
      pendingPhoneAfterEmail:
          pendingPhoneAfterEmail ?? this.pendingPhoneAfterEmail,
    );
  }
}

/// Authenticated user identity representation for Spliqo.
@immutable
class UserModel {
  const new({
    required this.id,
    required this.displayName,
    this.email,
    this.maskedPhone,
    this.emailVerified = false,
    this.phoneVerified = false,
  });

  final String id;
  final String displayName;
  final String? email;
  final String? maskedPhone;
  final bool emailVerified;
  final bool phoneVerified;

  UserModel copyWith({
    String? id,
    String? displayName,
    String? email,
    String? maskedPhone,
    bool? emailVerified,
    bool? phoneVerified,
  }) {
    return UserModel(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      maskedPhone: maskedPhone ?? this.maskedPhone,
      emailVerified: emailVerified ?? this.emailVerified,
      phoneVerified: phoneVerified ?? this.phoneVerified,
    );
  }
}

/// Authentication & user identity state.
@immutable
class AppAuthState {
  const new({
    this.user,
    this.authToken,
    this.isInitializing = false,
    this.isLoading = false,
    this.errorMessage,
    this.pendingOtp,
  });

  final UserModel? user;
  final String? authToken;
  final bool isInitializing;
  final bool isLoading;
  final String? errorMessage;
  final PendingOtpContext? pendingOtp;

  bool get isAuthenticated =>
      user != null && authToken != null && authToken!.isNotEmpty;
  bool get hasDisplayName => user?.displayName.trim().isNotEmpty == true;

  AppAuthState copyWith({
    UserModel? user,
    String? authToken,
    bool? isInitializing,
    bool? isLoading,
    String? errorMessage,
    PendingOtpContext? pendingOtp,
    bool clearUser = false,
    bool clearPendingOtp = false,
    bool clearError = false,
  }) {
    return AppAuthState(
      user: clearUser ? null : (user ?? this.user),
      authToken: clearUser ? null : (authToken ?? this.authToken),
      isInitializing: isInitializing ?? this.isInitializing,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pendingOtp: clearPendingOtp ? null : (pendingOtp ?? this.pendingOtp),
    );
  }
}

/// Provider for [AuthRepository].
final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>((ref) {
  return AuthRepository(
    supabase: ref.watch(supabaseClientProvider),
    apiClient: ref.watch(apiClientProvider),
  );
});

/// Listenable bridge allowing GoRouter to refresh redirects on auth state changes.
class AuthRouterRefreshNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

final Provider<AuthRouterRefreshNotifier> authRouterRefreshProvider =
    Provider<AuthRouterRefreshNotifier>((ref) {
  final notifier = AuthRouterRefreshNotifier();
  ref
    ..listen<AppAuthState>(authNotifierProvider, (prev, next) {
      if (prev?.isAuthenticated != next.isAuthenticated ||
          prev?.isInitializing != next.isInitializing) {
        notifier.notify();
      }
    })
    ..onDispose(notifier.dispose);
  return notifier;
});

/// Strictly authenticated auth state notifier backed by Supabase Auth + KeyStore.
class AuthNotifier extends Notifier<AppAuthState> {
  Future<void>? _initFuture;
  StreamSubscription<supa.AuthState>? _authSubscription;

  SecureStorageService get _secureStorage =>
      ref.read(secureStorageServiceProvider);
  AuthRepository get _authRepository => ref.read(authRepositoryProvider);

  @override
  AppAuthState build() {
    unawaited(_authSubscription?.cancel());
    _authSubscription = _authRepository.onAuthStateChange.listen((event) {
      unawaited(_handleSupabaseAuthEvent(event));
    });
    ref.onDispose(() {
      unawaited(_authSubscription?.cancel());
    });

    unawaited(initAuth());
    return const AppAuthState(isInitializing: true);
  }

  Future<void> _handleSupabaseAuthEvent(supa.AuthState authEvent) async {
    final session = authEvent.session;
    if (authEvent.event == supa.AuthChangeEvent.signedOut || session == null) {
      if (state.isAuthenticated) {
        await _secureStorage.clearAll();
        state = const AppAuthState();
      }
      return;
    }

    if (authEvent.event == supa.AuthChangeEvent.signedIn ||
        authEvent.event == supa.AuthChangeEvent.tokenRefreshed ||
        authEvent.event == supa.AuthChangeEvent.userUpdated) {
      await _applySupabaseSession(session);
    }
  }

  Future<void> initAuth() {
    return _initFuture ??= _performInitAuth();
  }

  Future<void> _performInitAuth() async {
    try {
      final session = _authRepository.currentSession;
      if (session != null && !session.isExpired) {
        await _applySupabaseSession(session);
        return;
      }

      // Restore cached credentials only if a real non-dummy token exists;
      // otherwise remain unauthenticated so the user signs in cleanly.
      final savedUserId = await _secureStorage.getUserId();
      final savedToken = await _secureStorage.getAuthToken();
      final savedName = await _secureStorage.getUserDisplayName();
      if (savedUserId != null &&
          savedToken != null &&
          savedToken.isNotEmpty &&
          savedToken != 'dev-local-offline-token') {
        state = AppAuthState(
          user: UserModel(
            id: savedUserId,
            displayName: savedName ?? '',
          ),
          authToken: savedToken,
        );
        return;
      }

      if (savedToken == 'dev-local-offline-token') {
        await _secureStorage.clearAll();
      }

      state = const AppAuthState();
    } on Object catch (e) {
      state = AppAuthState(
        errorMessage: 'Auth initialization error: $e',
      );
    }
  }

  Future<void> _applySupabaseSession(
    supa.Session session, {
    String? preferredDisplayName,
    String? verifiedPhoneE164,
  }) async {
    final supaUser = session.user;
    final savedName = await _secureStorage.getUserDisplayName();
    final meta = supaUser.userMetadata ?? const <String, dynamic>{};
    final metaName = (meta['display_name'] ??
            meta['full_name'] ??
            meta['name'] ??
            '')
        .toString();

    final resolvedName = AuthValidators.normalizeDisplayName(
      preferredDisplayName ??
          (metaName.isNotEmpty ? metaName : (savedName ?? '')),
    );

    await _secureStorage.saveUserId(supaUser.id);
    await _secureStorage.saveAuthToken(session.accessToken);
    if (resolvedName.isNotEmpty) {
      await _secureStorage.saveUserDisplayName(resolvedName);
    }

    final maskedFromSupabase = supaUser.phone != null && supaUser.phone!.isNotEmpty
        ? _maskPhone(supaUser.phone!)
        : null;

    state = state.copyWith(
      user: UserModel(
        id: supaUser.id,
        displayName: resolvedName.isNotEmpty ? resolvedName : 'Spliqo User',
        email: supaUser.email,
        maskedPhone: maskedFromSupabase ?? state.user?.maskedPhone,
        emailVerified: supaUser.emailConfirmedAt != null,
        phoneVerified: supaUser.phoneConfirmedAt != null,
      ),
      authToken: session.accessToken,
      isInitializing: false,
      isLoading: false,
      clearError: true,
    );

    // Best-effort sync to backend FLE profile table if backend is reachable
    if (resolvedName.isNotEmpty || verifiedPhoneE164 != null) {
      final profile = await _authRepository.syncUserProfile(
        displayName: resolvedName.isNotEmpty ? resolvedName : 'Spliqo User',
        phoneNumber: verifiedPhoneE164,
      );
      if (profile != null && state.user != null) {
        state = state.copyWith(
          user: state.user!.copyWith(
            displayName: (profile['display_name'] as String?) ??
                state.user!.displayName,
            maskedPhone: (profile['masked_phone_number'] as String?) ??
                state.user!.maskedPhone,
          ),
        );
      }
    }
  }

  String _maskPhone(String phone) {
    if (phone.length <= 4) {
      return '••••';
    }
    final prefix = phone.startsWith('+') && phone.length > 7
        ? phone.substring(0, 3)
        : '';
    final lastFour = phone.substring(phone.length - 4);
    final hiddenCount = (phone.length - prefix.length - 4).clamp(4, 10);
    return '$prefix${'•' * hiddenCount}$lastFour';
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(clearError: true);
    }
  }

  /// Signs in with Email + Password.
  /// Returns `true` if authenticated immediately, or `false` if email OTP verification is needed.
  Future<bool> signInWithPassword({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final normalizedEmail = AuthValidators.normalizeEmail(email);
      final res = await _authRepository.signInWithPassword(
        email: normalizedEmail,
        password: password,
      );
      final session = res.session;
      if (session != null) {
        await _applySupabaseSession(session);
        return true;
      }

      state = state.copyWith(
        isLoading: false,
        pendingOtp: PendingOtpContext(
          kind: OtpFlowKind.signupEmail,
          email: normalizedEmail,
        ),
      );
      return false;
    } on Failure catch (f) {
      if (f.code == 'email_not_confirmed') {
        final normalizedEmail = AuthValidators.normalizeEmail(email);
        state = state.copyWith(
          isLoading: false,
          errorMessage: f.message,
          pendingOtp: PendingOtpContext(
            kind: OtpFlowKind.signupEmail,
            email: normalizedEmail,
          ),
        );
        return false;
      }
      state = state.copyWith(isLoading: false, errorMessage: f.message);
      return false;
    } on Object catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Sign in failed: $e',
      );
      return false;
    }
  }

  /// Registers a new user with display_name, email, password, and phone number.
  /// Returns `true` when signup request succeeds (caller proceeds to OTP verification
  /// unless session is already returned immediately).
  Future<bool> signUpWithEmail({
    required String displayName,
    required String email,
    required String password,
    String? phone,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final cleanName = AuthValidators.normalizeDisplayName(displayName);
      final cleanEmail = AuthValidators.normalizeEmail(email);
      final cleanPhone =
          phone != null ? AuthValidators.normalizePhoneE164(phone) : '';

      final res = await _authRepository.signUpWithEmail(
        displayName: cleanName,
        email: cleanEmail,
        password: password,
      );

      final session = res.session;
      if (session != null) {
        await _applySupabaseSession(
          session,
          preferredDisplayName: cleanName,
        );
        if (cleanPhone.isNotEmpty) {
          await requestPhoneVerification(
            phone: cleanPhone,
            fromSignup: true,
          );
          return true;
        }
        return true;
      }

      state = state.copyWith(
        isLoading: false,
        pendingOtp: PendingOtpContext(
          kind: OtpFlowKind.signupEmail,
          email: cleanEmail,
          displayName: cleanName,
          pendingPhoneAfterEmail: cleanPhone.isNotEmpty ? cleanPhone : null,
        ),
      );
      return true;
    } on Failure catch (f) {
      state = state.copyWith(isLoading: false, errorMessage: f.message);
      return false;
    } on Object catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Registration failed: $e',
      );
      return false;
    }
  }

  /// Sends a passwordless 6-digit Email OTP for login.
  Future<bool> sendEmailLoginOtp({required String email}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final cleanEmail = AuthValidators.normalizeEmail(email);
      await _authRepository.sendEmailOtp(email: cleanEmail);
      state = state.copyWith(
        isLoading: false,
        pendingOtp: PendingOtpContext(
          kind: OtpFlowKind.loginEmail,
          email: cleanEmail,
        ),
      );
      return true;
    } on Failure catch (f) {
      state = state.copyWith(isLoading: false, errorMessage: f.message);
      return false;
    } on Object catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not send email code: $e',
      );
      return false;
    }
  }

  /// Sends a passwordless 6-digit SMS OTP for login.
  Future<bool> sendPhoneLoginOtp({required String phone}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final cleanPhone = AuthValidators.normalizePhoneE164(phone);
      await _authRepository.sendPhoneOtp(phone: cleanPhone);
      state = state.copyWith(
        isLoading: false,
        pendingOtp: PendingOtpContext(
          kind: OtpFlowKind.loginPhone,
          phone: cleanPhone,
        ),
      );
      return true;
    } on Failure catch (f) {
      state = state.copyWith(isLoading: false, errorMessage: f.message);
      return false;
    } on Object catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not send SMS code: $e',
      );
      return false;
    }
  }

  /// Initiates SMS OTP verification to bind/verify a phone number on the current account.
  Future<bool> requestPhoneVerification({
    required String phone,
    bool fromSignup = false,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final cleanPhone = AuthValidators.normalizePhoneE164(phone);
      await _authRepository.requestPhoneVerification(phone: cleanPhone);
      state = state.copyWith(
        isLoading: false,
        pendingOtp: PendingOtpContext(
          kind: fromSignup ? OtpFlowKind.signupPhone : OtpFlowKind.linkPhone,
          phone: cleanPhone,
          displayName: state.user?.displayName,
        ),
      );
      return true;
    } on Failure catch (f) {
      state = state.copyWith(isLoading: false, errorMessage: f.message);
      return false;
    } on Object catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not send phone verification code: $e',
      );
      return false;
    }
  }

  /// Sends a password recovery Email OTP.
  Future<bool> sendPasswordResetOtp({required String email}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final cleanEmail = AuthValidators.normalizeEmail(email);
      await _authRepository.sendPasswordResetOtp(email: cleanEmail);
      state = state.copyWith(
        isLoading: false,
        pendingOtp: PendingOtpContext(
          kind: OtpFlowKind.passwordRecovery,
          email: cleanEmail,
        ),
      );
      return true;
    } on Failure catch (f) {
      state = state.copyWith(isLoading: false, errorMessage: f.message);
      return false;
    } on Object catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not send reset code: $e',
      );
      return false;
    }
  }

  /// Verifies the active OTP token.
  /// Returns `'done'`, `'next_phone'`, `'reset_password'`, or `null` on error.
  Future<String?> verifyPendingOtp({required String token}) async {
    final pending = state.pendingOtp;
    if (pending == null) {
      return null;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final otpType = switch (pending.kind) {
        OtpFlowKind.signupEmail => supa.OtpType.signup,
        OtpFlowKind.loginEmail => supa.OtpType.email,
        OtpFlowKind.passwordRecovery => supa.OtpType.recovery,
        OtpFlowKind.loginPhone => supa.OtpType.sms,
        OtpFlowKind.signupPhone || OtpFlowKind.linkPhone => supa.OtpType.phoneChange,
      };

      final res = await _authRepository.verifyOtp(
        type: otpType,
        token: token.trim(),
        email: pending.email,
        phone: pending.phone,
      );

      final session = res.session ?? _authRepository.currentSession;
      if (session != null) {
        await _applySupabaseSession(
          session,
          preferredDisplayName: pending.displayName,
          verifiedPhoneE164: pending.isPhoneStep ? pending.phone : null,
        );
      }

      if (pending.kind == OtpFlowKind.passwordRecovery) {
        state = state.copyWith(isLoading: false);
        return 'reset_password';
      }

      if (pending.kind == OtpFlowKind.signupEmail &&
          pending.pendingPhoneAfterEmail != null &&
          pending.pendingPhoneAfterEmail!.isNotEmpty) {
        final sent = await requestPhoneVerification(
          phone: pending.pendingPhoneAfterEmail!,
          fromSignup: true,
        );
        if (sent) {
          return 'next_phone';
        }
        // Keep session authenticated even if SMS provider isn't active yet,
        // and let user see the SMS send error or continue to Home.
        return null;
      }

      state = state.copyWith(isLoading: false, clearPendingOtp: true);
      return 'done';
    } on Failure catch (f) {
      state = state.copyWith(isLoading: false, errorMessage: f.message);
      return null;
    } on Object catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Verification failed: $e',
      );
      return null;
    }
  }

  /// Resends the OTP for the active verification step.
  Future<bool> resendPendingOtp() async {
    final pending = state.pendingOtp;
    if (pending == null) {
      return false;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      switch (pending.kind) {
        case OtpFlowKind.signupEmail:
          await _authRepository.resendOtp(
            type: supa.OtpType.signup,
            email: pending.email,
          );
        case OtpFlowKind.loginEmail:
          await _authRepository.sendEmailOtp(email: pending.email!);
        case OtpFlowKind.loginPhone:
          await _authRepository.sendPhoneOtp(phone: pending.phone!);
        case OtpFlowKind.signupPhone:
        case OtpFlowKind.linkPhone:
          await _authRepository.requestPhoneVerification(phone: pending.phone!);
        case OtpFlowKind.passwordRecovery:
          await _authRepository.sendPasswordResetOtp(email: pending.email!);
      }
      state = state.copyWith(isLoading: false);
      return true;
    } on Failure catch (f) {
      state = state.copyWith(isLoading: false, errorMessage: f.message);
      return false;
    } on Object catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not resend code: $e',
      );
      return false;
    }
  }

  /// Completes password reset after recovery OTP verification.
  Future<bool> completePasswordReset({required String newPassword}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _authRepository.updatePassword(newPassword: newPassword);
      state = state.copyWith(isLoading: false, clearPendingOtp: true);
      return true;
    } on Failure catch (f) {
      state = state.copyWith(isLoading: false, errorMessage: f.message);
      return false;
    } on Object catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not update password: $e',
      );
      return false;
    }
  }

  /// Signs in (or registers) via native Google Sign-In.
  Future<bool> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _authRepository.signInWithGoogle();
      final session = res.session;
      if (session == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Google sign-in did not establish a session.',
        );
        return false;
      }

      await _applySupabaseSession(session);
      return true;
    } on AuthCanceledException {
      state = state.copyWith(isLoading: false);
      return false;
    } on Failure catch (f) {
      state = state.copyWith(isLoading: false, errorMessage: f.message);
      return false;
    } on Object catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Google Sign-In failed: $e',
      );
      return false;
    }
  }

  /// Sets or updates the user's table display name and persists to KeyStore.
  Future<void> updateDisplayName(String displayName) async {
    final cleanName = AuthValidators.normalizeDisplayName(displayName);
    if (cleanName.isEmpty) {
      return;
    }

    if (state.user != null) {
      state = state.copyWith(
        user: state.user!.copyWith(displayName: cleanName),
      );
    }

    try {
      await _secureStorage.saveUserDisplayName(cleanName);
      if (state.user != null) {
        await _authRepository.syncUserProfile(displayName: cleanName);
      }
    } on Object catch (e) {
      state = state.copyWith(
        errorMessage: 'Could not sync display name: $e',
      );
    }
  }

  void skipPendingPhoneVerification() {
    state = state.copyWith(clearPendingOtp: true, clearError: true);
  }

  /// Clears stored credentials and signs out of Supabase & Google.
  Future<void> signOut() async {
    try {
      await _authRepository.signOut();
    } on Object catch (_) {
      // Proceed with local wipe even if network sign-out fails.
    }
    try {
      await _secureStorage.clearAll();
    } on Object catch (_) {
      // Ignore secure storage wipe errors on sign-out.
    }
    _initFuture = null;
    state = const AppAuthState();
  }
}

/// Global provider for [AuthNotifier].
final NotifierProvider<AuthNotifier, AppAuthState> authNotifierProvider =
    NotifierProvider<AuthNotifier, AppAuthState>(AuthNotifier.new);
