import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spliqo/core/constants/app_strings.dart';
import 'package:spliqo/core/constants/app_tokens.dart';
import 'package:spliqo/core/router/route_paths.dart';
import 'package:spliqo/core/theme/app_colors.dart';
import 'package:spliqo/core/theme/app_gradients.dart';
import 'package:spliqo/core/theme/app_typography.dart';
import 'package:spliqo/state/auth_provider.dart';

/// Aesthetic animated launch splash screen for Spliqo.
///
/// Orchestrates a single cohesive entrance:
/// 1. Soft ambient radial aura
/// 2. Logo medallion scale-in with a subtle ripple ring
/// 3. Wordmark and tagline slide-up & fade
/// 4. Minimal progress bar before transitioning smoothly to [AppRoutes.home]
///    (when authenticated) or [AppRoutes.login] (when signed out).
class SplashScreen extends ConsumerStatefulWidget {
  const new({
    super.key,
    this.minimumDuration = const Duration(milliseconds: 1700),
    this.onFinished,
  });

  /// Minimum time the splash remains visible so the entrance completes smoothly.
  final Duration minimumDuration;

  /// Optional callback invoked when the splash finishes (useful for testing).
  /// When null, navigates to [AppRoutes.home] or [AppRoutes.login] via GoRouter.
  final VoidCallback? onFinished;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _auraOpacity;
  late final Animation<double> _auraScale;

  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;

  late final Animation<double> _ringScale;
  late final Animation<double> _ringOpacity;

  late final Animation<double> _textOpacity;
  late final Animation<Offset> _textSlide;

  late final Animation<double> _progressValue;

  Timer? _navigationTimer;
  bool _hasCompleted = false;
  bool _animationsInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    );

    _auraOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.50, curve: Curves.easeOut),
    );
    _auraScale = Tween<double>(begin: 0.82, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.65, curve: Curves.easeOutCubic),
      ),
    );

    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.06, 0.42, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.84, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.06, 0.52, curve: Curves.easeOutBack),
      ),
    );

    _ringScale = Tween<double>(begin: 0.92, end: 1.48).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.22, 0.72, curve: Curves.easeOutCubic),
      ),
    );
    _ringOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 0.35)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.35, end: 0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 70,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.22, 0.72),
      ),
    );

    _textOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.28, 0.66, curve: Curves.easeOut),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.22),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.28, 0.70, curve: Curves.easeOutExpo),
      ),
    );

    _progressValue = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.98, curve: Curves.easeInOutCubic),
    );

    _navigationTimer = Timer(widget.minimumDuration, _finishSplash);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_animationsInitialized) {
      return;
    }
    _animationsInitialized = true;

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  Future<void> _finishSplash() async {
    if (!mounted || _hasCompleted) {
      return;
    }
    _hasCompleted = true;

    if (widget.onFinished != null) {
      widget.onFinished!();
      return;
    }

    await ref.read(authNotifierProvider.notifier).initAuth();
    if (!mounted) {
      return;
    }
    final isAuthenticated = ref.read(authNotifierProvider).isAuthenticated;
    context.go(isAuthenticated ? AppRoutes.home : AppRoutes.login);
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canvasColor = isDark ? AppColors.canvasDark : AppColors.canvasLight;
    final titleColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final subtitleColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final trackColor =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;

    return Scaffold(
      backgroundColor: canvasColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Soft ambient radial background glow
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Opacity(
                opacity: _auraOpacity.value,
                child: Transform.scale(
                  scale: _auraScale.value,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned(
                        top: -120,
                        right: -90,
                        child: _AmbientOrb(
                          size: 320,
                          color: AppColors.radiantViolet
                              .withValues(alpha: isDark ? 0.20 : 0.12),
                        ),
                      ),
                      Positioned(
                        bottom: -100,
                        left: -80,
                        child: _AmbientOrb(
                          size: 280,
                          color: AppColors.electricSky
                              .withValues(alpha: isDark ? 0.16 : 0.10),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Centered brand emblem + wordmark + progress bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                children: [
                  const Spacer(flex: 5),

                  // Emblem with ripple ring
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Opacity(
                            opacity: _ringOpacity.value,
                            child: Transform.scale(
                              scale: _ringScale.value,
                              child: Container(
                                width: 124,
                                height: 124,
                                decoration: BoxDecoration(
                                  borderRadius: AppRadius.roundedCrystal,
                                  border: Border.all(
                                    color: AppColors.radiantVioletLight,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Opacity(
                            opacity: _logoOpacity.value,
                            child: Transform.scale(
                              scale: _logoScale.value,
                              child: child,
                            ),
                          ),
                        ],
                      );
                    },
                    child: Hero(
                      tag: 'spliqo-brand-logo',
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          borderRadius: AppRadius.roundedCrystal,
                          boxShadow: isDark
                              ? [
                                  BoxShadow(
                                    color: AppColors.radiantViolet
                                        .withValues(alpha: 0.28),
                                    blurRadius: 32,
                                    offset: const Offset(0, 12),
                                  ),
                                ]
                              : AppShadows.crystalFloating,
                        ),
                        child: ClipRRect(
                          borderRadius: AppRadius.roundedCrystal,
                          child: Image.asset(
                            'assets/images/spliqo_logo.png',
                            fit: BoxFit.cover,
                            semanticLabel: AppStrings.appName,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // Wordmark and tagline
                  SlideTransition(
                    position: _textSlide,
                    child: FadeTransition(
                      opacity: _textOpacity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppStrings.appName,
                            style: AppTypography.displayLarge.copyWith(
                              color: titleColor,
                              fontSize: 34,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            AppStrings.appTagline,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMedium.copyWith(
                              color: subtitleColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(flex: 5),

                  // Minimal loading progress indicator
                  AnimatedBuilder(
                    animation: _progressValue,
                    builder: (context, _) {
                      return Container(
                        width: 132,
                        height: 4,
                        decoration: BoxDecoration(
                          color: trackColor,
                          borderRadius: AppRadius.roundedFull,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: _progressValue.value.clamp(0.06, 1.0),
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: AppGradients.primaryRadiance,
                                borderRadius: AppRadius.roundedFull,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const new({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
