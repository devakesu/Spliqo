import 'package:flutter/material.dart';
import 'package:spliqo/core/utils/currency_formatter.dart';

/// Smooth animated counter for running estimated or final share amounts in integer paise precision.
class AnimatedPaiseCounter extends StatelessWidget {
  const new({
    required this.amountPaise,
    this.style,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.easeOutCubic,
    super.key,
  });

  final int amountPaise;
  final TextStyle? style;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final effectiveDuration = disableAnimations ? Duration.zero : duration;

    return TweenAnimationBuilder<double>(
      key: const ValueKey('animated_paise_counter_tween'),
      tween: Tween<double>(end: amountPaise.toDouble()),
      duration: effectiveDuration,
      curve: curve,
      builder: (context, value, _) {
        return Text(
          CurrencyFormatter.formatPaise(value.round()),
          style: style,
        );
      },
    );
  }
}
