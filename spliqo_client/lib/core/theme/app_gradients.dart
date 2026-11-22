import 'package:flutter/material.dart';
import 'package:spliqo/core/theme/app_colors.dart';

/// Centralized gradients for crystal glass, primary actions, and playful cards.
abstract final class AppGradients {
  /// Primary vibrant radiance (Violet to Bubblegum Pink)
  static const LinearGradient primaryRadiance = LinearGradient(
    colors: [
      AppColors.radiantViolet,
      AppColors.bubblegumPink,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Secondary candy aura (Electric Sky to Radiant Violet)
  static const LinearGradient electricAura = LinearGradient(
    colors: [
      AppColors.electricSky,
      AppColors.radiantVioletLight,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Mint sparkle for payment confirmation & success states
  static const LinearGradient mintSparkle = LinearGradient(
    colors: [
      AppColors.mintFresh,
      AppColors.electricSky,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Sunset gradient for warm highlights
  static const LinearGradient warmSunset = LinearGradient(
    colors: [
      AppColors.sunbeamAmber,
      AppColors.bubblegumPink,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Crystal Glass Specular Border Highlight
  static const LinearGradient crystalBorder = LinearGradient(
    colors: [
      Color(0x99FFFFFF),
      Color(0x1AFFFFFF),
      Color(0x0DFFFFFF),
      Color(0x4DFFFFFF),
    ],
    stops: [0.0, 0.4, 0.7, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Dark Crystal Specular Border Highlight
  static const LinearGradient crystalBorderDark = LinearGradient(
    colors: [
      Color(0x4DFFFFFF),
      Color(0x0DFFFFFF),
      Color(0x05FFFFFF),
      Color(0x26FFFFFF),
    ],
    stops: [0.0, 0.4, 0.7, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
