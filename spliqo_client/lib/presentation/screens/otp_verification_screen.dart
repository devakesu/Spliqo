import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Unified, animated 6-digit OTP verification screen handling:
/// - Email signup confirmation -> Phone SMS verification (2-step)
/// - Passwordless Email OTP login & Phone SMS OTP login
/// - Phone verification from Profile
/// - Password Recovery OTP + new password step
class OtpVerificationScreen extends ConsumerStatefulWidget {
  const new({
    super.key,
    this.redirectTo,
  });

  final String? redirectTo;

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final _otpController = TextEditingController();
  final _otpFocusNode = FocusNode();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _passwordFormKey = GlobalKey<FormState>();

  Timer? _cooldownTimer;
  int _secondsRemaining = AuthValidators.otpResendCooldownSeconds;
  bool _inPasswordResetStep = false;
  bool _obscurePassword = true;
  String _livePassword = '';

  @override
  void initState() {
    super.initState();
    _startCooldown();
    _newPasswordController.addListener(() {
      if (_livePassword != _newPasswordController.text) {
        setState(() => _livePassword = _newPasswordController.text);
      }
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _otpController.dispose();
    _otpFocusNode.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() {
      _secondsRemaining = AuthValidators.otpResendCooldownSeconds;
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
      } else {
        setState(() => _secondsRemaining -= 1);
      }
    });
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (AuthValidators.validateOtp(code) != null) {
      return;
    }

    final result = await ref
        .read(authNotifierProvider.notifier)
        .verifyPendingOtp(token: code);

    if (!mounted) {
      return;
    }

    if (result == 'done') {
      _navigateAfterAuth();
    } else if (result == 'next_phone') {
      _otpController.clear();
      _startCooldown();
    } else if (result == 'reset_password') {
      setState(() => _inPasswordResetStep = true);
    }
  }

  Future<void> _resendCode() async {
    if (_secondsRemaining > 0) {
      return;
    }
    final ok = await ref.read(authNotifierProvider.notifier).resendPendingOtp();
    if (ok && mounted) {
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A fresh 6-digit code was sent.')),
      );
    }
  }

  Future<void> _submitNewPassword() async {
    if (!(_passwordFormKey.currentState?.validate() ?? false)) {
      return;
    }
    final ok = await ref
        .read(authNotifierProvider.notifier)
        .completePasswordReset(newPassword: _newPasswordController.text);
    if (ok && mounted) {
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
    final pending = authState.pendingOtp;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (pending == null && !_inPasswordResetStep) {
      return AuthScaffold(
        appBar: AppBar(backgroundColor: Colors.transparent),
        child: Column(
          children: [
            const Icon(
              Icons.verified_outlined,
              size: 48,
              color: AppColors.radiantViolet,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No verification pending',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            AuthPrimaryButton(
              label: 'Back to Sign In',
              onPressed: () => context.go(AppRoutes.login),
            ),
          ],
        ),
      );
    }

    final isTwoStepSignup = pending?.kind == OtpFlowKind.signupEmail &&
            (pending?.pendingPhoneAfterEmail?.isNotEmpty ?? false) ||
        pending?.kind == OtpFlowKind.signupPhone;
    final isPhoneStep = pending?.isPhoneStep ?? false;
    final targetDisplay = isPhoneStep
        ? (pending?.phone ?? '')
        : (pending?.email ?? '');

    return AuthScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: BackButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go(AppRoutes.login);
            }
          },
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: _inPasswordResetStep
            ? _buildPasswordResetCard(authState, theme, isDark)
            : _buildOtpCard(
                authState: authState,
                theme: theme,
                isDark: isDark,
                isTwoStepSignup: isTwoStepSignup,
                isPhoneStep: isPhoneStep,
                targetDisplay: targetDisplay,
                canSkipPhone: pending?.kind == OtpFlowKind.signupPhone &&
                    authState.isAuthenticated,
              ),
      ),
    );
  }

  Widget _buildOtpCard({
    required AppAuthState authState,
    required ThemeData theme,
    required bool isDark,
    required bool isTwoStepSignup,
    required bool isPhoneStep,
    required String targetDisplay,
    required bool canSkipPhone,
  }) {
    final otpDigits = _otpController.text;

    return Column(
      key: ValueKey('otp_step_${authState.pendingOtp?.kind}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isTwoStepSignup) ...[
          _VerificationStepIndicator(isPhoneStep: isPhoneStep),
          const SizedBox(height: AppSpacing.lg),
        ],
        Center(
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.radiantViolet.withValues(alpha: 0.2)
                  : AppColors.radiantVioletSoft,
              borderRadius: AppRadius.roundedXl,
            ),
            child: Icon(
              isPhoneStep
                  ? Icons.sms_outlined
                  : Icons.mark_email_read_outlined,
              size: 32,
              color: AppColors.radiantViolet,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          isPhoneStep ? 'Verify phone number' : AppStrings.verifyOtpTitle,
          textAlign: TextAlign.center,
          style: AppTypography.displayMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${isPhoneStep ? AppStrings.verifyPhoneOtpSubtitle : AppStrings.verifyEmailOtpSubtitle}\n$targetDisplay',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthErrorBanner(message: authState.errorMessage),

              // Accessible single TextField driving 6 animated visual PIN boxes
              GestureDetector(
                onTap: _otpFocusNode.requestFocus,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(AuthValidators.otpLength, (i) {
                        final hasDigit = i < otpDigits.length;
                        final isCurrent = i == otpDigits.length &&
                            _otpFocusNode.hasFocus;
                        final char = hasDigit ? otpDigits[i] : '';

                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 46,
                          height: 56,
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.surfaceVariantDark
                                : AppColors.canvasLight,
                            borderRadius: AppRadius.roundedMd,
                            border: Border.all(
                              color: isCurrent
                                  ? AppColors.radiantViolet
                                  : hasDigit
                                      ? AppColors.radiantVioletLight
                                      : (isDark
                                          ? const Color(0xFF334155)
                                          : const Color(0xFFCBD5E1)),
                              width: isCurrent ? 2 : 1.4,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              char,
                              style: AppTypography.headlineLarge.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    Opacity(
                      opacity: 0,
                      child: TextField(
                        controller: _otpController,
                        focusNode: _otpFocusNode,
                        autofocus: true,
                        maxLength: AuthValidators.otpLength,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(
                            AuthValidators.otpLength,
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {});
                          if (value.length == AuthValidators.otpLength) {
                            unawaited(_verifyOtp());
                          }
                        },
                        decoration: const InputDecoration(
                          counterText: '',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),
              AuthPrimaryButton(
                label: 'Verify code',
                isLoading: authState.isLoading,
                onPressed: authState.isLoading ||
                        otpDigits.length < AuthValidators.otpLength
                    ? null
                    : _verifyOtp,
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: _secondsRemaining > 0
                    ? Text(
                        'Resend code in 00:${_secondsRemaining.toString().padLeft(2, '0')}',
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark
                              ? AppColors.textMutedDark
                              : AppColors.textMutedLight,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : TextButton(
                        onPressed: authState.isLoading ? null : _resendCode,
                        child: const Text(
                          'Resend verification code',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
              ),
              if (canSkipPhone) ...[
                const SizedBox(height: AppSpacing.xs),
                TextButton(
                  onPressed: authState.isLoading
                      ? null
                      : () {
                          ref
                              .read(authNotifierProvider.notifier)
                              .skipPendingPhoneVerification();
                          _navigateAfterAuth();
                        },
                  child: Text(
                    'Verify phone later in Profile',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordResetCard(
    AppAuthState authState,
    ThemeData theme,
    bool isDark,
  ) {
    return Column(
      key: const ValueKey('password_reset_step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Set a new password',
          textAlign: TextAlign.center,
          style: AppTypography.displayMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Choose a strong password for your Spliqo account.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
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
          ),
          child: Form(
            key: _passwordFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthErrorBanner(message: authState.errorMessage),
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'New password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
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
                  obscureText: _obscurePassword,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                    prefixIcon: Icon(Icons.verified_user_outlined),
                  ),
                  validator: (val) => AuthValidators.validateConfirmPassword(
                    val,
                    _newPasswordController.text,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AuthPrimaryButton(
                  label: 'Update password',
                  isLoading: authState.isLoading,
                  onPressed: authState.isLoading ? null : _submitNewPassword,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VerificationStepIndicator extends StatelessWidget {
  const new({required this.isPhoneStep});

  final bool isPhoneStep;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StepBadge(
          step: '1',
          label: 'Email',
          active: !isPhoneStep,
          completed: isPhoneStep,
        ),
        Container(
          width: 28,
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          color: isPhoneStep ? AppColors.mintFresh : const Color(0xFFCBD5E1),
        ),
        _StepBadge(
          step: '2',
          label: 'Phone',
          active: isPhoneStep,
          completed: false,
        ),
      ],
    );
  }
}

class _StepBadge extends StatelessWidget {
  const new({
    required this.step,
    required this.label,
    required this.active,
    required this.completed,
  });

  final String step;
  final String label;
  final bool active;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final bg = completed
        ? AppColors.mintFresh
        : active
            ? AppColors.radiantViolet
            : const Color(0xFFE2E8F0);
    final fg = (completed || active) ? Colors.white : AppColors.textSecondaryLight;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Center(
            child: completed
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : Text(
                    step,
                    style: AppTypography.labelSmall.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
