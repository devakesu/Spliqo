import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:spliqo/core/constants/app_strings.dart';
import 'package:spliqo/presentation/widgets/crystal_navbar.dart';

/// Enterprise shell layout holding the persistent floating crystal navbar across root tabs.
class MainShellScaffold extends StatelessWidget {
  const new({
    required this.navigationShell,
    super.key,
  });

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: CrystalNavBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        items: const [
          CrystalNavItem(
            icon: Icons.receipt_long_outlined,
            activeIcon: Icons.receipt_long_rounded,
            label: AppStrings.navHome,
          ),
          CrystalNavItem(
            icon: Icons.add_rounded,
            activeIcon: Icons.camera_alt_rounded,
            label: AppStrings.navScan,
            isPrimary: true,
          ),
          CrystalNavItem(
            icon: Icons.group_add_outlined,
            activeIcon: Icons.group_add_rounded,
            label: AppStrings.navJoin,
          ),
          CrystalNavItem(
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded,
            label: AppStrings.navProfile,
          ),
        ],
      ),
    );
  }
}
