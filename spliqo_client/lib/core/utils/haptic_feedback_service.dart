import 'dart:async';

import 'package:flutter/services.dart';

/// Centralized service for tactile micro-interactions and haptic feedback.
abstract final class HapticFeedbackService {
  /// Selection tap when toggling bill item claims.
  static Future<void> selection() async {
    try {
      await HapticFeedback.selectionClick();
    } on Object catch (_) {
      // Gracefully ignore on unsupported platforms or test harnesses.
    }
  }

  /// Impact feedback for completion or confirmation actions.
  static Future<void> impact() async {
    try {
      await HapticFeedback.mediumImpact();
    } on Object catch (_) {
      // Gracefully ignore on unsupported platforms or test harnesses.
    }
  }

  /// Light impact for minor UI button taps.
  static Future<void> lightImpact() async {
    try {
      await HapticFeedback.lightImpact();
    } on Object catch (_) {
      // Gracefully ignore on unsupported platforms or test harnesses.
    }
  }

  /// Heavy impact for critical irreversible actions like finalising bill.
  static Future<void> heavyImpact() async {
    try {
      await HapticFeedback.heavyImpact();
    } on Object catch (_) {
      // Gracefully ignore on unsupported platforms or test harnesses.
    }
  }
}
