import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spliqo/core/storage/secure_storage_service.dart';
import 'package:spliqo/data/datasources/supabase_client_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// User identity representation for Spliqo.
class UserModel {
  const new({
    required this.id,
    required this.displayName,
    this.isAnonymous = true,
  });

  final String id;
  final String displayName;
  final bool isAnonymous;

  UserModel copyWith({
    String? id,
    String? displayName,
    bool? isAnonymous,
  }) {
    return UserModel(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      isAnonymous: isAnonymous ?? this.isAnonymous,
    );
  }
}

/// Authentication & user identity state.
class AuthState {
  const new({
    this.user,
    this.authToken,
    this.isLoading = false,
    this.errorMessage,
  });

  final UserModel? user;
  final String? authToken;
  final bool isLoading;
  final String? errorMessage;

  bool get isAuthenticated => user != null && authToken != null;
  bool get hasDisplayName => user?.displayName.trim().isNotEmpty == true;

  AuthState copyWith({
    UserModel? user,
    String? authToken,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AuthState(
      user: user ?? this.user,
      authToken: authToken ?? this.authToken,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

/// Enterprise auth notifier managing anonymous sign-in, hardware KeyStore persistence,
/// and user table sync.
class AuthNotifier extends Notifier<AuthState> {
  Future<void>? _initFuture;

  SecureStorageService get _secureStorage =>
      ref.read(secureStorageServiceProvider);
  SupabaseClient get _supabase => ref.read(supabaseClientProvider);

  @override
  AuthState build() {
    unawaited(initAuth());
    return const AuthState(isLoading: true);
  }

  Future<void> initAuth() {
    return _initFuture ??= _performInitAuth();
  }

  Future<void> _performInitAuth() async {
    try {
      // 1. Read hardware-encrypted credentials from KeyStore/Keychain
      final savedUserId = await _secureStorage.getUserId();
      final savedDisplayName = await _secureStorage.getUserDisplayName();
      final savedToken = await _secureStorage.getAuthToken();

      // 2. Check active Supabase session
      try {
        final currentSession = _supabase.auth.currentSession;
        if (currentSession != null) {
          final userId = currentSession.user.id;
          final token = currentSession.accessToken;

          await _secureStorage.saveUserId(userId);
          await _secureStorage.saveAuthToken(token);

          state = AuthState(
            user: UserModel(
              id: userId,
              displayName: savedDisplayName ?? '',
              isAnonymous: currentSession.user.isAnonymous,
            ),
            authToken: token,
          );
          return;
        }
      } on Object catch (_) {
        // Ignored if session check fails
      }

      // 3. If stored credentials exist, restore immediately for instant startup
      if (savedUserId != null && savedToken != null) {
        state = AuthState(
          user: UserModel(
            id: savedUserId,
            displayName: savedDisplayName ?? '',
          ),
          authToken: savedToken,
        );
        return;
      }

      // 4. Try seamless anonymous sign-in with Supabase
      try {
        final authResponse = await _supabase.auth.signInAnonymously();
        final user = authResponse.user;
        final session = authResponse.session;

        if (user != null && session != null) {
          await _secureStorage.saveUserId(user.id);
          await _secureStorage.saveAuthToken(session.accessToken);

          state = AuthState(
            user: UserModel(
              id: user.id,
              displayName: savedDisplayName ?? '',
              isAnonymous: user.isAnonymous,
            ),
            authToken: session.accessToken,
          );
          return;
        }
      } on Object catch (_) {
        // Offline or Supabase anonymous auth not configured:
        // Use locally generated secure identity stored in KeyStore
      }

      // 5. Fallback local guest identity if completely new and offline
      if (state.user == null) {
        final localUserId = const Uuid().v4();
        const localDummyToken = 'dev-local-offline-token';

        await _secureStorage.saveUserId(localUserId);
        await _secureStorage.saveAuthToken(localDummyToken);

        state = AuthState(
          user: UserModel(
            id: localUserId,
            displayName: savedDisplayName ?? '',
          ),
          authToken: localDummyToken,
        );
      }
    } on Object catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Auth initialization error: $e',
      );
    }
  }

  /// Sets or updates the user's table display name and persists to KeyStore.
  Future<void> updateDisplayName(String displayName) async {
    final cleanName = displayName.trim();
    if (cleanName.isEmpty) {
      return;
    }

    final updatedUser = state.user?.copyWith(displayName: cleanName) ??
        UserModel(
          id: const Uuid().v4(),
          displayName: cleanName,
        );

    state = state.copyWith(user: updatedUser);

    try {
      await _secureStorage.saveUserDisplayName(cleanName);

      // Best-effort sync to public.user_profiles if online
      if (_supabase.auth.currentSession != null) {
        unawaited(
          _supabase.from('user_profiles').upsert({
            'id': updatedUser.id,
            'display_name': cleanName,
          }),
        );
      }
    } on Object catch (e) {
      state = state.copyWith(
        errorMessage: 'Could not sync display name: $e',
      );
    }
  }

  /// Clears stored credentials and resets user identity.
  Future<void> signOut() async {
    try {
      await _secureStorage.clearAll();
      await _supabase.auth.signOut();
    } on Object catch (_) {
      // Ignored during sign-out
    }
    _initFuture = null;
    state = const AuthState();
  }
}

/// Global provider for [AuthNotifier].
final authNotifierProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
