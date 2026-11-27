import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spliqo/core/router/route_paths.dart';
import 'package:spliqo/presentation/screens/active_room_screen.dart';
import 'package:spliqo/presentation/screens/home_screen.dart';
import 'package:spliqo/presentation/screens/host_review_screen.dart';
import 'package:spliqo/presentation/screens/join_screen.dart';
import 'package:spliqo/presentation/screens/login_screen.dart';
import 'package:spliqo/presentation/screens/otp_verification_screen.dart';
import 'package:spliqo/presentation/screens/profile_screen.dart';
import 'package:spliqo/presentation/screens/receipt_review_screen.dart';
import 'package:spliqo/presentation/screens/settlement_screen.dart';
import 'package:spliqo/presentation/screens/signup_screen.dart';
import 'package:spliqo/presentation/screens/splash_screen.dart';
import 'package:spliqo/presentation/widgets/main_shell_scaffold.dart';
import 'package:spliqo/state/auth_provider.dart';

final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'rootNav');

/// Centralized GoRouter provider enforcing authenticated access across app routes.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ref.watch(authRouterRefreshProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authNotifierProvider);
      final location = state.uri.path;

      // Keep splash visible until its minimum animation finishes.
      if (location == AppRoutes.splash) {
        return null;
      }

      if (authState.isInitializing) {
        return null;
      }

      final isAuthRoute = location == AppRoutes.login ||
          location == AppRoutes.signup ||
          location == AppRoutes.verifyOtp;

      if (!authState.isAuthenticated) {
        if (isAuthRoute) {
          return null;
        }
        final fullPath = state.uri.toString();
        if (fullPath == AppRoutes.home || fullPath.isEmpty) {
          return AppRoutes.login;
        }
        return '${AppRoutes.login}?next=${Uri.encodeComponent(fullPath)}';
      }

      // Authenticated user: allow verify-otp only when linking phone or resetting password.
      if (location == AppRoutes.verifyOtp && authState.pendingOtp != null) {
        return null;
      }

      if (isAuthRoute) {
        final next = state.uri.queryParameters['next'];
        if (next != null && next.startsWith('/') && !next.startsWith('//')) {
          return next;
        }
        return AppRoutes.home;
      }

      return null;
    },
    routes: [
      // Launch Splash Screen
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: AppRoutes.splash,
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: const SplashScreen(),
          transitionDuration: const Duration(milliseconds: 350),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
        ),
      ),

      // Authentication Routes
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: AppRoutes.login,
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: LoginScreen(
            redirectTo: state.uri.queryParameters['next'],
          ),
          transitionDuration: const Duration(milliseconds: 280),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: AppRoutes.signup,
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: SignupScreen(
            redirectTo: state.uri.queryParameters['next'],
          ),
          transitionDuration: const Duration(milliseconds: 280),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: AppRoutes.verifyOtp,
        builder: (context, state) => OtpVerificationScreen(
          redirectTo: state.uri.queryParameters['next'],
        ),
      ),

      // 4-Tab Stateful Shell with persistent floating crystal navbar
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShellScaffold(navigationShell: navigationShell);
        },
        branches: [
          // Tab 0: Home / Activity
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          // Tab 1: Create / Receipt Scan
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.create,
                builder: (context, state) => const ReceiptReviewScreen(),
              ),
            ],
          ),
          // Tab 2: Join
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.join,
                builder: (context, state) => const JoinScreen(),
              ),
            ],
          ),
          // Tab 3: Profile
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // Direct Deep Link Join (/join/:token)
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: AppRoutes.joinWithToken,
        builder: (context, state) {
          final token = state.pathParameters['token'];
          return JoinScreen(initialToken: token);
        },
      ),

      // Screen 2: Active Room & Item Selection (/room/:id)
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: AppRoutes.activeRoom,
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return ActiveRoomScreen(sessionId: id);
        },
      ),

      // Screen 3: Host Review & Resolution (/room/:id/review)
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: AppRoutes.hostReview,
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return HostReviewScreen(sessionId: id);
        },
      ),

      // Screen 4: Final Settlement & Shares (/room/:id/settle)
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: AppRoutes.settlement,
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return SettlementScreen(sessionId: id);
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page Not Found')),
      body: Center(
        child: Text('Route ${state.uri} does not exist.'),
      ),
    ),
  );
});
