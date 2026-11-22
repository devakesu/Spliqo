import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spliqo/core/constants/app_tokens.dart';
import 'package:spliqo/core/router/route_paths.dart';
import 'package:spliqo/core/theme/app_colors.dart';
import 'package:spliqo/core/theme/app_gradients.dart';
import 'package:spliqo/presentation/screens/active_room_screen.dart';
import 'package:spliqo/state/auth_provider.dart';
import 'package:spliqo/state/session_providers.dart';

/// Modal bottom sheet allowing users to quickly join a dining session using a 6-char code.
class JoinRoomSheet extends ConsumerStatefulWidget {
  const new({this.initialToken, super.key});

  final String? initialToken;

  static Future<void> show(BuildContext context, {String? initialToken}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => JoinRoomSheet(initialToken: initialToken),
    );
  }

  @override
  ConsumerState<JoinRoomSheet> createState() => _JoinRoomSheetState();
}

class _JoinRoomSheetState extends ConsumerState<JoinRoomSheet> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

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

  Future<void> _join() async {
    final code = _codeController.text.trim().toUpperCase();
    final name = _nameController.text.trim();

    if (code.isEmpty) {
      setState(() => _errorMessage = 'Please enter a 6-character room code.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter your name at the table.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Ensure display name is saved
      await ref.read(authNotifierProvider.notifier).updateDisplayName(name);

      // 2. Call backend join endpoint
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
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + bottomInset,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? Colors.white24
                    : Colors.black12,
                borderRadius: AppRadius.roundedFull,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                gradient: AppGradients.electricAura,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.group_add_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Join Dinner Split',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Enter the 6-character room code shared by your host.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.brightness == Brightness.dark
                  ? AppColors.textMutedDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              LengthLimitingTextInputFormatter(16),
            ],
            decoration: const InputDecoration(
              hintText: 'e.g. SPL7X2',
              prefixIcon: Icon(Icons.tag_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Your name at table',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: const BoxDecoration(
                color: AppColors.errorRedSoft,
                borderRadius: AppRadius.roundedSm,
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
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            onPressed: _isLoading ? null : _join,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Join Room'),
          ),
        ],
      ),
    );
  }
}
