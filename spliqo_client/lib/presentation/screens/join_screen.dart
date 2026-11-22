import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spliqo/core/constants/app_strings.dart';
import 'package:spliqo/core/constants/app_tokens.dart';
import 'package:spliqo/core/router/route_paths.dart';
import 'package:spliqo/core/theme/app_colors.dart';
import 'package:spliqo/core/theme/app_gradients.dart';
import 'package:spliqo/presentation/screens/active_room_screen.dart';
import 'package:spliqo/state/auth_provider.dart';
import 'package:spliqo/state/session_providers.dart';

/// Screen allowing guests to enter a 6-character room code or join via token.
class JoinScreen extends ConsumerStatefulWidget {
  const new({this.initialToken, super.key});

  final String? initialToken;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  bool get _isDeepLink => widget.initialToken != null;

  @override
  void initState() {
    super.initState();
    if (widget.initialToken != null) {
      _codeController.text = widget.initialToken!;
    }
    final savedName = ref.read(authNotifierProvider).user?.displayName;
    if (savedName != null && savedName.isNotEmpty) {
      _nameController.text = savedName;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleJoin() async {
    final code = _codeController.text.trim().toUpperCase();
    final name = _nameController.text.trim();

    if (code.isEmpty) {
      setState(() => _errorMessage = 'Please enter a valid room code.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter your display name.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Persist user's table display name strictly to KeyStore
      await ref.read(authNotifierProvider.notifier).updateDisplayName(name);

      // 2. Call backend participant join API
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post(
        '/sessions/join',
        body: {
          'invite_token': code,
          'display_name': name,
        },
      );

      final sessionId = response['session_id'] as String;
      if (mounted) {
        if (GoRouter.maybeOf(context) != null) {
          unawaited(context.push(AppRoutes.room(sessionId)));
        } else {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ActiveRoomScreen(sessionId: sessionId),
            ),
          );
        }
      }
    } on Exception catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not join session: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isDeepLink ? 'Dinner Invitation' : AppStrings.joinTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Deep Link Invitation Card or Standard Join Icon
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(
                  gradient: AppGradients.electricAura,
                  borderRadius: AppRadius.roundedXl,
                  boxShadow: AppShadows.softCard,
                ),
                child: Center(
                  child: Icon(
                    _isDeepLink
                        ? Icons.restaurant_rounded
                        : Icons.connect_without_contact_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _isDeepLink ? "You're Invited to Dinner!" : 'Join Dinner Table',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _isDeepLink
                  ? 'Accept the invitation to claim what you consume in real-time.'
                  : 'Enter the 6-character room code from your host or scan table QR.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.textMutedDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Token / Room Code Card
            if (_isDeepLink) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.radiantViolet.withValues(alpha: 0.15)
                      : AppColors.radiantVioletSoft,
                  borderRadius: AppRadius.roundedLg,
                  border: Border.all(
                    color: AppColors.radiantViolet.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.key_rounded,
                      color: AppColors.radiantViolet,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Room Code: ${_codeController.text}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.radiantViolet,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ] else ...[
              Text(
                'Room Code',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(16),
                ],
                decoration: InputDecoration(
                  hintText: 'e.g. SPL7X2',
                  prefixIcon: const Icon(Icons.tag_rounded),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    tooltip: 'Scan QR Code',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Camera QR scanner ready for dining table QR codes.',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // Display Name Input
            Text(
              'Your Name at Table',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'e.g. Alex',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.errorRedSoft,
                  borderRadius: AppRadius.roundedSm,
                  border: Border.all(
                    color: AppColors.errorRed.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: AppColors.errorRed,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xl),

            // Submit Button
            ElevatedButton(
              onPressed: _isLoading ? null : _handleJoin,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isDeepLink ? 'Accept & Join Table' : AppStrings.joinRoomCTA,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
