import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spliqo/core/constants/app_tokens.dart';
import 'package:spliqo/core/theme/app_colors.dart';
import 'package:spliqo/core/theme/app_gradients.dart';
import 'package:spliqo/state/auth_provider.dart';

/// Modal bottom sheet prompting the user for their table display name.
class NamePromptSheet extends ConsumerStatefulWidget {
  const new({this.initialName, super.key});

  final String? initialName;

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NamePromptSheet(),
    );
  }

  @override
  ConsumerState<NamePromptSheet> createState() => _NamePromptSheetState();
}

class _NamePromptSheetState extends ConsumerState<NamePromptSheet> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    final authUser = ref.read(authNotifierProvider).user;
    _controller = TextEditingController(
      text: widget.initialName ?? authUser?.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a name so friends recognize you.');
      return;
    }

    await ref.read(authNotifierProvider.notifier).updateDisplayName(name);
    if (mounted) {
      Navigator.of(context).pop(name);
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
                gradient: AppGradients.primaryRadiance,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('👋', style: TextStyle(fontSize: 26)),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'What should we call you?',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'This name appears on the live room and item claims.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.brightness == Brightness.dark
                  ? AppColors.textMutedDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'e.g. Alex, Sam, Pri',
              prefixIcon: const Icon(Icons.badge_outlined),
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            onPressed: _save,
            child: const Text('Continue to Table'),
          ),
        ],
      ),
    );
  }
}
