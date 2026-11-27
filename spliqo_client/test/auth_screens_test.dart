import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spliqo/core/constants/app_strings.dart';
import 'package:spliqo/core/router/app_router.dart';
import 'package:spliqo/core/storage/secure_storage_service.dart';
import 'package:spliqo/data/datasources/api_client.dart';
import 'package:spliqo/presentation/screens/login_screen.dart';
import 'package:spliqo/presentation/screens/signup_screen.dart';
import 'package:spliqo/state/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_test.dart';
import 'secure_storage_test.dart';

void main() {
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

  group('Auth UI & Router Guard Tests', () {
    testWidgets('LoginScreen renders modes and Google Sign-In button',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageServiceProvider
                .overrideWithValue(secureStorageService),
            authRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.loginTitle), findsOneWidget);
      expect(find.text('Password'), findsNWidgets(2));
      expect(find.text('Email OTP'), findsOneWidget);
      expect(find.text('Phone OTP'), findsOneWidget);
      expect(find.text(AppStrings.continueWithGoogle), findsOneWidget);

      // Switch to Phone OTP tab
      await tester.tap(find.text('Phone OTP'));
      await tester.pumpAndSettle();
      expect(find.text('Send SMS code'), findsOneWidget);
    });

    testWidgets('SignupScreen renders all DB fields and password meter',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageServiceProvider
                .overrideWithValue(secureStorageService),
            authRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: const MaterialApp(home: SignupScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Display name'), findsOneWidget);
      expect(find.text('Email address'), findsOneWidget);
      expect(find.text('Phone number (verified via SMS OTP)'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm password'), findsOneWidget);
      expect(find.text(AppStrings.signUpWithGoogle), findsOneWidget);
      expect(find.text('10+ chars'), findsOneWidget);
    });

    testWidgets('Unauthenticated app launch routes from splash to login',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageServiceProvider
                .overrideWithValue(secureStorageService),
            authRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              final router = ref.watch(routerProvider);
              return MaterialApp.router(routerConfig: router);
            },
          ),
        ),
      );

      // Splash displays initially
      expect(find.text(AppStrings.appName), findsOneWidget);

      // Wait for Splash minimumDuration (1700ms) + transition
      await tester.pump(const Duration(milliseconds: 1800));
      await tester.pumpAndSettle();

      // Should land on LoginScreen, NOT HomeScreen
      expect(find.text(AppStrings.loginTitle), findsOneWidget);
      expect(find.text(AppStrings.startNewSplitCTA), findsNothing);
    });
  });
}
