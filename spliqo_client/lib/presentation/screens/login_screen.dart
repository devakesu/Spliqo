import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spliqo/core/constants/app_strings.dart';
import 'package:spliqo/core/constants/app_tokens.dart';
import 'package:spliqo/core/router/route_paths.dart';
import 'package:spliqo/core/theme/app_colors.dart';
import 'package:spliqo/core/theme/app_typography.dart';
import 'package:spliqo/core/validation/auth_validators.dart';
import 'package:spliqo/presentation/widgets/auth_widgets.dart';
import 'package:spliqo/state/auth_provider.dart';

enum _LoginMode { password, emailOtp, phoneOtp }

/// Aesthetic animated Login screen supporting Email+Password, Email OTP,
/// Phone SMS OTP, Password Recovery, and native Google Sign-In.
class LoginScreen extends ConsumerStatefulWidget {
  const new({
    super.key,
    this.redirectTo,
  });

  final String? redirectTo;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

  _LoginMode _mode = _LoginMode.password;
  bool _obscurePassword = true;
  bool _googleLoading = false;

  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  bool _didInitMotion = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 580),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOutExpo,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitMotion) {
      return;
    }
    _didInitMotion = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _entranceController.value = 1;
    } else {
      _entranceController.forward();
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _switchMode(_LoginMode next) {
    if (_mode == next) {
      return;
    }
    ref.read(authNotifierProvider.notifier).clearError();
    setState(() => _mode = next);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final notifier = ref.read(authNotifierProvider.notifier);

    switch (_mode) {
      case _LoginMode.password:
        final ok = await notifier.signInWithPassword(
          email: _emailController.text,
          password: _passwordController.text,
        );
        if (!mounted) {
          return;
        }
        if (ok) {
          _navigateAfterAuth();
        } else if (ref.read(authNotifierProvider).pendingOtp != null) {
          _openVerifyOtp();
        }

      case _LoginMode.emailOtp:
        final sent = await notifier.sendEmailLoginOtp(
          email: _emailController.text,
        );
        if (sent && mounted) {
          _openVerifyOtp();
        }

      case _LoginMode.phoneOtp:
        final sent = await notifier.sendPhoneLoginOtp(
          phone: _phoneController.text,
        );
        if (sent && mounted) {
          _openVerifyOtp();
        }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _googleLoading = true);
    final ok = await ref.read(authNotifierProvider.notifier).signInWithGoogle();
    if (!mounted) {
      return;
    }
    setState(() => _googleLoading = false);
    if (ok) {
      _navigateAfterAuth();
    }
  }

  Future<void> _showForgotPasswordSheet() async {
    final resetEmailController =
        TextEditingController(text: _emailController.text.trim());
    final sheetKey = GlobalKey<FormState>();

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            MediaQuery.viewInsetsOf(sheetCtx).bottom + AppSpacing.lg,
          ),
          child: Form(
            key: sheetKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Reset password',
                  style: Theme.of(sheetCtx).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'We will send a 6-digit recovery code to your registered email.',
                  style: Theme.of(sheetCtx).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondaryLight,
                      ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: resetEmailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    hintText: 'you@example.com',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                  validator: AuthValidators.validateEmail,
                ),
                const SizedBox(height: AppSpacing.lg),
                AuthPrimaryButton(
                  label: 'Send recovery code',
                  onPressed: () {
                    if (sheetKey.currentState?.validate() ?? false) {
                      Navigator.of(sheetCtx).pop(true);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    final email = resetEmailController.text;
    resetEmailController.dispose();

    if (submitted == true && mounted) {
      final sent = await ref
          .read(authNotifierProvider.notifier)
          .sendPasswordResetOtp(email: email);
      if (sent && mounted) {
        _openVerifyOtp();
      }
    }
  }

  void _navigateAfterAuth() {
    final target = widget.redirectTo;
    if (target != null && target.startsWith('/') && !target.startsWith('//')) {
      context.go(target);
    } else {
      context.go(AppRoutes.home);
    }
  }

  void _openVerifyOtp() {
    final nextParam = widget.redirectTo != null
        ? '?next=${Uri.encodeComponent(widget.redirectTo!)}'
        : '';
    unawaited(context.push('${AppRoutes.verifyOtp}$nextParam'));
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final busy = authState.isLoading || _googleLoading;

    return AuthScaffold(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Brand Header
              Center(
                child: Hero(
                  tag: 'spliqo-brand-logo',
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: const BoxDecoration(
                      borderRadius: AppRadius.roundedLg,
                      boxShadow: AppShadows.crystalFloating,
                    ),
                    child: ClipRRect(
                      borderRadius: AppRadius.roundedLg,
                      child: Image.asset(
                        'assets/images/spliqo_logo.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                AppStrings.loginTitle,
                textAlign: TextAlign.center,
                style: AppTypography.displayMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppStrings.loginSubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Mode selector pill
              _LoginModeSelector(
                mode: _mode,
                onChanged: _switchMode,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Main Form Card
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                  borderRadius: AppRadius.roundedXl,
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFE2E8F0),
                  ),
                  boxShadow: isDark ? null : AppShadows.softCard,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AuthErrorBanner(message: authState.errorMessage),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: _buildModeFields(theme),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AuthPrimaryButton(
                        label: switch (_mode) {
                          _LoginMode.password => 'Sign in',
                          _LoginMode.emailOtp => 'Send email code',
                          _LoginMode.phoneOtp => 'Send SMS code',
                        },
                        isLoading: authState.isLoading && !_googleLoading,
                        onPressed: busy ? null : _submit,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),
              const AuthDivider(),
              const SizedBox(height: AppSpacing.md),

              GoogleSignInButton(
                label: AppStrings.continueWithGoogle,
                isLoading: _googleLoading,
                onPressed: busy ? null : _handleGoogleSignIn,
              ),

              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'New to Spliqo?',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () {
                            ref
                                .read(authNotifierProvider.notifier)
                                .clearError();
                            final nextParam = widget.redirectTo != null
                                ? '?next=${Uri.encodeComponent(widget.redirectTo!)}'
                                : '';
                            context.go('${AppRoutes.signup}$nextParam');
                          },
                    child: const Text(
                      'Create an account',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeFields(ThemeData theme) {
    switch (_mode) {
      case _LoginMode.password:
        return Column(
          key: const ValueKey('password_mode'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email address',
                hintText: 'you@example.com',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              validator: AuthValidators.validateEmail,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (val) => (val == null || val.isEmpty)
                  ? 'Password is required.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _showForgotPasswordSheet,
                child: Text(
                  'Forgot password?',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.radiantViolet,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        );

      case _LoginMode.emailOtp:
        return Column(
          key: const ValueKey('email_otp_mode'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Email address',
                hintText: 'you@example.com',
                helperText: 'We will email you a 6-digit one-time code.',
                prefixIcon: Icon(Icons.mark_email_read_outlined),
              ),
              validator: AuthValidators.validateEmail,
            ),
          ],
        );

      case _LoginMode.phoneOtp:
        return Column(
          key: const ValueKey('phone_otp_mode'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumber],
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '+91 98765 43210',
                helperText: '10-digit Indian mobile or E.164 with country code.',
                prefixIcon: Icon(Icons.phone_android_rounded),
              ),
              validator: AuthValidators.validatePhone,
            ),
          ],
        );
    }
  }
}

class _LoginModeSelector extends StatelessWidget {
  const new({
    required this.mode,
    required this.onChanged,
  });

  final _LoginMode mode;
  final ValueChanged<_LoginMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;
    final pillColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    final alignment = switch (mode) {
      _LoginMode.password => Alignment.centerLeft,
      _LoginMode.emailOtp => Alignment.center,
      _LoginMode.phoneOtp => Alignment.centerRight,
    };

    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: AppRadius.roundedFull,
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: alignment,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: FractionallySizedBox(
              widthFactor: 1 / 3,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: pillColor,
                  borderRadius: AppRadius.roundedFull,
                  boxShadow: isDark ? null : AppShadows.softCard,
                ),
              ),
            ),
          ),
          Row(
            children: [
              _ModeTab(
                label: 'Password',
                selected: mode == _LoginMode.password,
                onTap: () => onChanged(_LoginMode.password),
              ),
              _ModeTab(
                label: 'Email OTP',
                selected: mode == _LoginMode.emailOtp,
                onTap: () => onChanged(_LoginMode.emailOtp),
              ),
              _ModeTab(
                label: 'Phone OTP',
                selected: mode == _LoginMode.phoneOtp,
                onTap: () => onChanged(_LoginMode.phoneOtp),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = selected
        ? (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight)
        : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight);

    return Expanded(
      child: InkWell(
        borderRadius: AppRadius.roundedFull,
        onTap: onTap,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: AppTypography.labelMedium.copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              letterSpacing: 0.1,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}
