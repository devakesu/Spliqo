import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spliqo/core/constants/app_strings.dart';
import 'package:spliqo/presentation/screens/splash_screen.dart';

void main() {
  group('SplashScreen Widget Tests', () {
    testWidgets('renders logo, app name, tagline and invokes onFinished',
        (tester) async {
      var finished = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SplashScreen(
              minimumDuration: const Duration(milliseconds: 1600),
              onFinished: () {
                finished = true;
              },
            ),
          ),
        ),
      );

      expect(find.text(AppStrings.appName), findsOneWidget);
      expect(find.text(AppStrings.appTagline), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 800));
      expect(finished, isFalse);

      await tester.pump(const Duration(milliseconds: 900));
      expect(finished, isTrue);
    });

    testWidgets('respects reduced motion accessibility setting',
        (tester) async {
      var finished = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              home: SplashScreen(
                minimumDuration: const Duration(milliseconds: 300),
                onFinished: () {
                  finished = true;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text(AppStrings.appName), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 350));
      expect(finished, isTrue);
    });
  });
}
