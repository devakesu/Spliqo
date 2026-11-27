import 'package:flutter/material.dart';
import 'package:spliqo/core/constants/app_tokens.dart';
import 'package:spliqo/core/theme/app_colors.dart';
import 'package:spliqo/core/theme/app_gradients.dart';
import 'package:spliqo/core/theme/app_typography.dart';
import 'package:spliqo/core/validation/auth_validators.dart';

/// Shared ambient, responsive scaffold for Spliqo authentication screens.
class AuthScaffold extends StatelessWidget {
  const new({
    required this.child,
    super.key,
    this.appBar,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canvasColor = isDark ? AppColors.canvasDark : AppColors.canvasLight;

    return Scaffold(
      backgroundColor: canvasColor,
      extendBodyBehindAppBar: true,
      appBar: appBar,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -110,
            right: -90,
            child: _AmbientGlowOrb(
              size: 300,
              color: AppColors.radiantViolet
                  .withValues(alpha: isDark ? 0.22 : 0.11),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -80,
            child: _AmbientGlowOrb(
              size: 280,
              color: AppColors.electricSky
                  .withValues(alpha: isDark ? 0.16 : 0.09),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AutofillGroup(child: child),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientGlowOrb extends StatelessWidget {
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

/// Tactile primary gradient action button for auth flows.
class AuthPrimaryButton extends StatefulWidget {
  const new({
    required this.label,
    required this.onPressed,
    super.key,
    this.isLoading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  @override
  State<AuthPrimaryButton> createState() => _AuthPrimaryButtonState();
}

class _AuthPrimaryButtonState extends State<AuthPrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: (_pressed && !reduceMotion) ? 0.98 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            gradient: enabled ? AppGradients.primaryRadiance : null,
            color: enabled
                ? null
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: AppRadius.roundedFull,
            boxShadow: enabled ? AppShadows.primaryGlow : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: AppRadius.roundedFull,
              onTap: enabled ? widget.onPressed : null,
              child: Center(
                child: widget.isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(
                              widget.icon,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                          ],
                          Text(
                            widget.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tactile "Continue with Google" button featuring a custom-drawn Google "G" emblem.
class GoogleSignInButton extends StatefulWidget {
  const new({
    required this.label,
    required this.onPressed,
    super.key,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = widget.onPressed != null && !widget.isLoading;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: (_pressed && !reduceMotion) ? 0.98 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: AppRadius.roundedFull,
            border: Border.all(
              color: isDark
                  ? const Color(0xFF334155)
                  : const Color(0xFFE2E8F0),
              width: 1.5,
            ),
            boxShadow: isDark ? null : AppShadows.softCard,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: AppRadius.roundedFull,
              onTap: enabled ? widget.onPressed : null,
              child: Center(
                child: widget.isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CustomPaint(painter: _GoogleLogoPainter()),
                          ),
                          const SizedBox(width: AppSpacing.sm + 4),
                          Text(
                            widget.label,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  const new();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final stroke = w * 0.19;
    final rect = Rect.fromCircle(center: center, radius: (w - stroke) / 2);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..color = const Color(0xFF4285F4);

    // Blue right arc + crossbar
    canvas
      ..drawArc(rect, -0.18, 1.15, false, paint)
      ..drawLine(
        Offset(w * 0.50, h * 0.50),
        Offset(w * 0.94, h * 0.50),
        Paint()
          ..color = const Color(0xFF4285F4)
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );

    // Green bottom arc
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 0.92, 1.32, false, paint);

    // Yellow left arc
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 2.20, 1.45, false, paint);

    // Red top arc
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, 3.60, 1.95, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Animated inline error alert for authentication forms.
class AuthErrorBanner extends StatelessWidget {
  const new({
    required this.message,
    super.key,
  });

  final String? message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasError = message != null && message!.isNotEmpty;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: hasError
          ? Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 4,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.errorRed.withValues(alpha: 0.15)
                    : AppColors.errorRedSoft,
                borderRadius: AppRadius.roundedMd,
                border: Border.all(
                  color: AppColors.errorRed.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.errorRed,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      message!,
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark
                            ? const Color(0xFFFCA5A5)
                            : const Color(0xFFB91C1C),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// Real-time animated password strength meter + requirement chips.
class PasswordStrengthMeter extends StatelessWidget {
  const new({
    required this.password,
    super.key,
  });

  final String password;

  @override
  Widget build(BuildContext context) {
    final check = AuthValidators.evaluatePassword(password);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final activeColor = switch (check.strengthScore) {
      0 || 1 => AppColors.errorRed,
      2 => AppColors.sunbeamAmber,
      3 => AppColors.electricSky,
      _ => check.isValid ? AppColors.mintFresh : AppColors.electricSky,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  height: 4,
                  decoration: BoxDecoration(
                    color: (password.isNotEmpty && i < check.strengthScore)
                        ? activeColor
                        : (isDark
                            ? AppColors.surfaceVariantDark
                            : const Color(0xFFE2E8F0)),
                    borderRadius: AppRadius.roundedFull,
                  ),
                ),
              ),
              if (i < 3) const SizedBox(width: 6),
            ],
            const SizedBox(width: AppSpacing.sm),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                password.isEmpty ? 'Min 10 chars' : check.strengthLabel,
                key: ValueKey(
                  password.isEmpty ? 'empty' : check.strengthLabel,
                ),
                style: AppTypography.labelSmall.copyWith(
                  color: password.isEmpty
                      ? (isDark
                          ? AppColors.textMutedDark
                          : AppColors.textMutedLight)
                      : activeColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _RequirementChip(
              label: '10+ chars',
              met: check.hasMinLength && check.hasMaxLength,
            ),
            _RequirementChip(label: 'Uppercase', met: check.hasUppercase),
            _RequirementChip(label: 'Lowercase', met: check.hasLowercase),
            _RequirementChip(label: 'Number', met: check.hasDigit),
            _RequirementChip(label: 'Symbol', met: check.hasSymbol),
          ],
        ),
      ],
    );
  }
}

class _RequirementChip extends StatelessWidget {
  const new({
    required this.label,
    required this.met,
  });

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = met
        ? (isDark
            ? AppColors.mintFresh.withValues(alpha: 0.18)
            : AppColors.mintFreshSoft)
        : (isDark
            ? AppColors.surfaceVariantDark
            : AppColors.surfaceVariantLight);
    final fgColor = met
        ? AppColors.mintFresh
        : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: AppRadius.roundedFull,
        border: Border.all(
          color: met
              ? AppColors.mintFresh.withValues(alpha: 0.45)
              : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 13,
            color: fgColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: fgColor,
              fontWeight: met ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean "or continue with" divider.
class AuthDivider extends StatelessWidget {
  const new({
    super.key,
    this.text = 'or continue with',
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Row(
      children: [
        Expanded(child: Divider(color: lineColor, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            text,
            style: AppTypography.bodySmall.copyWith(
              color: textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: Divider(color: lineColor, thickness: 1)),
      ],
    );
  }
}
