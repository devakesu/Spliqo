import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spliqo/core/config/app_config.dart';
import 'package:spliqo/core/constants/app_strings.dart';
import 'package:spliqo/core/constants/app_tokens.dart';
import 'package:spliqo/core/router/route_paths.dart';
import 'package:spliqo/core/storage/secure_storage_service.dart';
import 'package:spliqo/core/theme/app_colors.dart';
import 'package:spliqo/core/theme/app_gradients.dart';
import 'package:spliqo/core/validation/auth_validators.dart';
import 'package:spliqo/state/auth_provider.dart';
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

  Future<void> _promptVerifyPhone() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(sheetCtx).bottom + AppSpacing.lg,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Verify phone number',
                style: Theme.of(sheetCtx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'We will send a 6-digit SMS code and store your number encrypted via KMS.',
                style: Theme.of(sheetCtx).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: controller,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '+91 98765 43210',
                  prefixIcon: Icon(Icons.phone_android_rounded),
                ),
                validator: AuthValidators.validatePhone,
              ),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: () {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.of(sheetCtx).pop(true);
                  }
                },
                child: const Text('Send SMS Code'),
              ),
            ],
          ),
        ),
      ),
    );

    final phone = controller.text;
    controller.dispose();

    if (confirmed == true && mounted) {
      final sent = await ref
          .read(authNotifierProvider.notifier)
          .requestPhoneVerification(phone: phone);
      if (sent && mounted) {
        unawaited(context.push(AppRoutes.verifyOtp));
      } else if (mounted) {
        final err = ref.read(authNotifierProvider).errorMessage;
        if (err != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(err)));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authState = ref.watch(authNotifierProvider);
    final user = authState.user;

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
                      child: Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 40,
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
              (user?.displayName.isNotEmpty ?? false)
                  ? user!.displayName
                  : 'Spliqo Member',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (user?.email != null && user!.email!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                user.email!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                if (user?.emailVerified ?? false)
                  const Chip(
                    avatar: Icon(
                      Icons.verified_rounded,
                      size: 16,
                      color: AppColors.mintFresh,
                    ),
                    label: Text('Email Verified'),
                  ),
                if (user?.phoneVerified ?? false)
                  Chip(
                    avatar: const Icon(
                      Icons.phone_android_rounded,
                      size: 16,
                      color: AppColors.mintFresh,
                    ),
                    label: Text(user?.maskedPhone ?? 'Phone Verified'),
                  )
                else
                  ActionChip(
                    avatar: const Icon(
                      Icons.add_call,
                      size: 16,
                      color: AppColors.radiantViolet,
                    ),
                    label: const Text('Verify Phone'),
                    onPressed: _promptVerifyPhone,
                  ),
              ],
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

            const SizedBox(height: AppSpacing.xl),

            OutlinedButton.icon(
              onPressed: () async {
                await ref.read(authNotifierProvider.notifier).signOut();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.errorRed,
                side: BorderSide(
                  color: AppColors.errorRed.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Sign out'),
            ),

            const SizedBox(height: AppSpacing.lg),

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
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}
