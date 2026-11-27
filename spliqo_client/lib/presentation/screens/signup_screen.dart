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

/// Aesthetic animated Sign Up screen covering all DB user fields:
/// `public.user_profiles` (`display_name`, FLE-encrypted `phone_number`) +
/// `auth.users` (`email`, `password`, email & phone OTP verification) + Google.
class SignupScreen extends ConsumerStatefulWidget {
  const new({
    super.key,
    this.redirectTo,
  });

  final String? redirectTo;

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _googleLoading = false;
  String _livePassword = '';

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
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    if (_livePassword != _passwordController.text) {
      setState(() => _livePassword = _passwordController.text);
    }
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
    _passwordController.removeListener(_onPasswordChanged);
    _entranceController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final ok = await ref.read(authNotifierProvider.notifier).signUpWithEmail(
          displayName: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          phone: _phoneController.text,
        );

    if (!ok || !mounted) {
      return;
    }

    final authState = ref.read(authNotifierProvider);
    if (authState.pendingOtp != null) {
      final nextParam = widget.redirectTo != null
          ? '?next=${Uri.encodeComponent(widget.redirectTo!)}'
          : '';
      unawaited(context.push('${AppRoutes.verifyOtp}$nextParam'));
      return;
    }

    if (authState.isAuthenticated) {
      _navigateAfterAuth();
    }
  }

  Future<void> _handleGoogleSignUp() async {
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

  void _navigateAfterAuth() {
    final target = widget.redirectTo;
    if (target != null && target.startsWith('/') && !target.startsWith('//')) {
      context.go(target);
    } else {
      context.go(AppRoutes.home);
    }
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
                    width: 60,
                    height: 60,
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
              const SizedBox(height: AppSpacing.md),
              Text(
                AppStrings.signupTitle,
                textAlign: TextAlign.center,
                style: AppTypography.displayMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppStrings.signupSubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Sign Up Card
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
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        maxLength: AuthValidators.maxDisplayNameLength,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                          hintText: 'How friends see you at the table',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                          counterText: '',
                        ),
                        validator: AuthValidators.validateDisplayName,
                      ),
                      const SizedBox(height: AppSpacing.md),
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
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        decoration: const InputDecoration(
                          labelText: 'Phone number (verified via SMS OTP)',
                          hintText: '+91 98765 43210',
                          helperText: 'Encrypted at rest with hardware-backed KMS.',
                          prefixIcon: Icon(Icons.phone_android_rounded),
                        ),
                        validator: AuthValidators.validatePhone,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () {
                              setState(
                                () => _obscurePassword = !_obscurePassword,
                              );
                            },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: AuthValidators.validatePassword,
                      ),
                      PasswordStrengthMeter(password: _livePassword),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirm,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.newPassword],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: const Icon(Icons.verified_user_outlined),
                          suffixIcon: IconButton(
                            tooltip: _obscureConfirm
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () {
                              setState(
                                () => _obscureConfirm = !_obscureConfirm,
                              );
                            },
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (val) =>
                            AuthValidators.validateConfirmPassword(
                          val,
                          _passwordController.text,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        AppStrings.privacyClaimsNotice,
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark
                              ? AppColors.textMutedDark
                              : AppColors.textMutedLight,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AuthPrimaryButton(
                        label: 'Create account',
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
                label: AppStrings.signUpWithGoogle,
                isLoading: _googleLoading,
                onPressed: busy ? null : _handleGoogleSignUp,
              ),

              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Already have an account?',
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
                            context.go('${AppRoutes.login}$nextParam');
                          },
                    child: const Text(
                      'Sign in',
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
}
