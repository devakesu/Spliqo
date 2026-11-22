import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spliqo/core/constants/app_strings.dart';
import 'package:spliqo/presentation/widgets/crystal_navbar.dart';

void main() {
  group('CrystalNavBar Widget Tests', () {
    testWidgets('renders all 4 tabs including center primary action',
        (tester) async {
      var tappedIndex = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: CrystalNavBar(
              currentIndex: 0,
              onTap: (index) {
                tappedIndex = index;
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
          ),
        ),
      );

      // Verify all tabs exist
      expect(find.text(AppStrings.navHome), findsOneWidget);
      expect(find.text(AppStrings.navScan), findsOneWidget);
      expect(find.text(AppStrings.navJoin), findsNothing); // inactive without label
      expect(find.byIcon(Icons.group_add_outlined), findsOneWidget);
      expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);

      // Tap Join tab
      await tester.tap(find.byIcon(Icons.group_add_outlined));
      await tester.pump();
      expect(tappedIndex, equals(2));

      // Tap Center primary Split action
      await tester.tap(find.text(AppStrings.navScan));
      await tester.pump();
      expect(tappedIndex, equals(1));
    });
  });
}
