import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spliqo/core/constants/app_tokens.dart';
import 'package:spliqo/core/theme/app_colors.dart';
import 'package:spliqo/core/theme/app_gradients.dart';

/// Navigation item model for [CrystalNavBar].
class CrystalNavItem {
  const new({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.isPrimary = false,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isPrimary;
}

/// Floating, frosted crystal-glass bottom navigation bar.
class CrystalNavBar extends StatelessWidget {
  const new({
    required this.currentIndex,
    required this.onTap,
    required this.items,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<CrystalNavItem> items;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Container(
          decoration: const BoxDecoration(
            borderRadius: AppRadius.roundedCrystal,
            boxShadow: AppShadows.crystalFloating,
          ),
          child: ClipRRect(
            borderRadius: AppRadius.roundedCrystal,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs + 2,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.crystalFrostDark
                      : AppColors.crystalFrostLight,
                  borderRadius: AppRadius.roundedCrystal,
                  border: Border.all(
                    color: isDark
                        ? AppColors.crystalBorderDark
                        : AppColors.crystalBorderLight,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(items.length, (index) {
                    final item = items[index];
                    final isSelected = index == currentIndex;

                    if (item.isPrimary) {
                      return _buildPrimaryAction(context, item, isSelected, () {
                        unawaited(HapticFeedback.mediumImpact());
                        onTap(index);
                      });
                    }

                    return _buildNavItem(context, item, isSelected, () {
                      unawaited(HapticFeedback.selectionClick());
                      onTap(index);
                    });
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    CrystalNavItem item,
    bool isSelected,
    VoidCallback onPressed,
  ) {
    final theme = Theme.of(context);
    const activeColor = AppColors.radiantViolet;
    final inactiveColor = theme.brightness == Brightness.dark
        ? AppColors.textMutedDark
        : AppColors.textSecondaryLight;

    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? (theme.brightness == Brightness.dark
                  ? AppColors.radiantViolet.withValues(alpha: 0.25)
                  : AppColors.radiantVioletSoft)
              : Colors.transparent,
          borderRadius: AppRadius.roundedFull,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? item.activeIcon : item.icon,
              size: 22,
              color: isSelected ? activeColor : inactiveColor,
            ),
            if (isSelected) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                item.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: activeColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryAction(
    BuildContext context,
    CrystalNavItem item,
    bool isSelected,
    VoidCallback onPressed,
  ) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md + 2,
          vertical: AppSpacing.sm,
        ),
        decoration: const BoxDecoration(
          gradient: AppGradients.primaryRadiance,
          borderRadius: AppRadius.roundedFull,
          boxShadow: AppShadows.primaryGlow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.activeIcon,
              size: 20,
              color: Colors.white,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              item.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
