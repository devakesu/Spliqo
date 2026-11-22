import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spliqo/core/config/app_config.dart';
import 'package:spliqo/core/constants/app_strings.dart';
import 'package:spliqo/core/constants/app_tokens.dart';
import 'package:spliqo/core/storage/secure_storage_service.dart';
import 'package:spliqo/core/theme/app_colors.dart';
import 'package:spliqo/core/theme/app_gradients.dart';
import 'package:spliqo/state/session_providers.dart';

/// Screen allowing the host to manage their payout UPI ID and security settings.
class ProfileScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _upiController = TextEditingController();
  bool _isSaving = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedUpi());
  }

  @override
  void dispose() {
    _upiController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedUpi() async {
    final secureStorage = ref.read(secureStorageServiceProvider);
    final savedUpi = await secureStorage.getHostPayoutUpi();
    if (savedUpi != null && mounted) {
      _upiController.text = savedUpi;
    }
  }

  Future<void> _saveUpi() async {
    final upiId = _upiController.text.trim();
    if (upiId.isEmpty || !upiId.contains('@')) {
      setState(() {
        _statusMessage = 'Please enter a valid UPI VPA (e.g. name@okhdfcbank)';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });

    try {
      // 1. Save locally to strict hardware-backed SecureStorage
      final secureStorage = ref.read(secureStorageServiceProvider);
      await secureStorage.saveHostPayoutUpi(upiId);

      // 2. Sync to Backend FLE Payout Profile (AES-256-GCM bytea)
      final paymentRepo = ref.read(paymentRepositoryProvider);
      await paymentRepo.setPayoutProfile(upiId);

      setState(() {
        _isSaving = false;
        _isSuccess = true;
        _statusMessage = 'UPI ID securely encrypted & saved!';
      });
    } on Exception catch (e) {
      setState(() {
        _isSaving = false;
        _isSuccess = false;
        _statusMessage = 'Could not save payout profile: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.profileTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // User Avatar & Name Card
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: const BoxDecoration(
                      gradient: AppGradients.primaryRadiance,
                      shape: BoxShape.circle,
                      boxShadow: AppShadows.primaryGlow,
                    ),
                    child: const Center(
                      child: Text(
                        '👤',
                        style: TextStyle(fontSize: 40),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xxs + 2),
                    decoration: BoxDecoration(
                      color: AppColors.mintFresh,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.scaffoldBackgroundColor,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Host Coordinator',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Hardware KeyStore Security Status Badge
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.mintFresh.withValues(alpha: 0.15)
                    : AppColors.mintFreshSoft,
                borderRadius: AppRadius.roundedLg,
                border: Border.all(
                  color: AppColors.mintFresh.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    color: AppColors.mintFresh,
                    size: 20,
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      AppStrings.securityBadge,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.mintFresh,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Payout UPI Setup Section
            Text(
              AppStrings.payoutSettingsTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              AppStrings.payoutSettingsSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark
                    ? AppColors.textMutedDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            TextField(
              controller: _upiController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'e.g. yourname@oksbi',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            if (_statusMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: _isSuccess
                      ? AppColors.finalBadgeBackground
                      : AppColors.errorRedSoft,
                  borderRadius: AppRadius.roundedSm,
                ),
                child: Text(
                  _statusMessage!,
                  style: TextStyle(
                    color: _isSuccess
                        ? AppColors.finalBadgeText
                        : AppColors.errorRed,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveUpi,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: _isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(AppStrings.saveUpiCTA),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // App Version Info
            Center(
              child: Text(
                'Spliqo v${AppConfig.current.appVersion} (${AppConfig.current.environment})',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppColors.textMutedDark
                      : AppColors.textMutedLight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
