import 'package:flutter/foundation.dart';

/// Password requirement breakdown aligned with Supabase Auth & shared/limits.json.
@immutable
class PasswordCheckResult {
  const new({
    required this.hasMinLength,
    required this.hasMaxLength,
    required this.hasUppercase,
    required this.hasLowercase,
    required this.hasDigit,
    required this.hasSymbol,
  });

  final bool hasMinLength;
  final bool hasMaxLength;
  final bool hasUppercase;
  final bool hasLowercase;
  final bool hasDigit;
  final bool hasSymbol;

  /// Number of complexity criteria satisfied (0..4 excluding max-length guard).
  int get strengthScore {
    var score = 0;
    if (hasMinLength) {
      score++;
    }
    if (hasUppercase && hasLowercase) {
      score++;
    }
    if (hasDigit) {
      score++;
    }
    if (hasSymbol) {
      score++;
    }
    return score;
  }

  bool get isValid =>
      hasMinLength &&
      hasMaxLength &&
      hasUppercase &&
      hasLowercase &&
      hasDigit &&
      hasSymbol;

  String get strengthLabel {
    switch (strengthScore) {
      case 0:
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      default:
        return isValid ? 'Strong' : 'Almost there';
    }
  }
}

/// Client-side input validators matching server Pydantic & Postgres constraints.
abstract final class AuthValidators {
  static const int minDisplayNameLength = 1;
  static const int maxDisplayNameLength = 40;
  static const int minPasswordLength = 10;
  static const int maxPasswordLength = 72;
  static const int otpLength = 6;
  static const int otpResendCooldownSeconds = 60;

  static final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');
  static final RegExp _emailRegex = RegExp(
    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
  );
  static final RegExp _e164Regex = RegExp(r'^\+[1-9]\d{6,14}$');
  static final RegExp _indianTenDigitRegex = RegExp(r'^[6-9]\d{9}$');
  static final RegExp _uppercaseRegex = RegExp('[A-Z]');
  static final RegExp _lowercaseRegex = RegExp('[a-z]');
  static final RegExp _digitRegex = RegExp('[0-9]');
  static final RegExp _symbolRegex = RegExp(r'''[!@#$%^&*()\-_=+\[\]{};:'",.<>/?\\|`~]''');
  static final RegExp _otpRegex = RegExp(r'^\d{6}$');

  /// Strips control characters and trims surrounding whitespace.
  static String normalizeDisplayName(String raw) {
    return raw.replaceAll(_controlChars, '').trim();
  }

  static String? validateDisplayName(String? value) {
    final cleaned = normalizeDisplayName(value ?? '');
    if (cleaned.length < minDisplayNameLength) {
      return 'Display name is required.';
    }
    if (cleaned.length > maxDisplayNameLength) {
      return 'Display name must be at most $maxDisplayNameLength characters.';
    }
    return null;
  }

  static String normalizeEmail(String raw) => raw.trim().toLowerCase();

  static String? validateEmail(String? value) {
    final email = normalizeEmail(value ?? '');
    if (email.isEmpty) {
      return 'Email address is required.';
    }
    if (email.length > 254 || !_emailRegex.hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  /// Normalizes spaces/hyphens and assumes +91 for bare 10-digit Indian mobiles.
  static String normalizePhoneE164(String raw) {
    final compact = raw.replaceAll(RegExp(r'[\s\-()]+'), '').trim();
    if (compact.isEmpty) {
      return '';
    }
    if (_indianTenDigitRegex.hasMatch(compact)) {
      return '+91$compact';
    }
    if (RegExp(r'^91[6-9]\d{9}$').hasMatch(compact)) {
      return '+$compact';
    }
    return compact;
  }

  static String? validatePhone(String? value, {bool required = true}) {
    final normalized = normalizePhoneE164(value ?? '');
    if (normalized.isEmpty) {
      return required ? 'Phone number is required.' : null;
    }
    if (!_e164Regex.hasMatch(normalized)) {
      return 'Enter a valid phone number with country code (e.g. +919876543210).';
    }
    return null;
  }

  static PasswordCheckResult evaluatePassword(String password) {
    return PasswordCheckResult(
      hasMinLength: password.length >= minPasswordLength,
      hasMaxLength: password.length <= maxPasswordLength,
      hasUppercase: _uppercaseRegex.hasMatch(password),
      hasLowercase: _lowercaseRegex.hasMatch(password),
      hasDigit: _digitRegex.hasMatch(password),
      hasSymbol: _symbolRegex.hasMatch(password),
    );
  }

  static String? validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) {
      return 'Password is required.';
    }
    final check = evaluatePassword(password);
    if (!check.hasMinLength) {
      return 'Password must be at least $minPasswordLength characters.';
    }
    if (!check.hasMaxLength) {
      return 'Password must be at most $maxPasswordLength characters.';
    }
    if (!check.hasUppercase ||
        !check.hasLowercase ||
        !check.hasDigit ||
        !check.hasSymbol) {
      return 'Include uppercase, lowercase, a number, and a symbol.';
    }
    return null;
  }

  static String? validateConfirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password.';
    }
    if (value != password) {
      return 'Passwords do not match.';
    }
    return null;
  }

  static String? validateOtp(String? value) {
    final token = (value ?? '').trim();
    if (!_otpRegex.hasMatch(token)) {
      return 'Enter the 6-digit verification code.';
    }
    return null;
  }
}
