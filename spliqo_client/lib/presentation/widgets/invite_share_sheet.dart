import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:spliqo/core/constants/app_tokens.dart';
import 'package:spliqo/core/router/route_paths.dart';
import 'package:spliqo/core/theme/app_colors.dart';
import 'package:spliqo/presentation/screens/active_room_screen.dart';

/// Modal bottom sheet presented to the host upon room activation,
/// providing one-tap link sharing, native share sheet, and table QR code.
class InviteShareSheet extends StatelessWidget {
  const new({
    required this.sessionId,
    required this.roomCode,
    this.sessionTitle = 'Dinner Table',
    super.key,
  });

  final String sessionId;
  final String roomCode;
  final String sessionTitle;

  String get _inviteUrl => 'https://spliqo.app/join/$roomCode';

  static Future<void> show(
    BuildContext context, {
    required String sessionId,
    required String roomCode,
    String sessionTitle = 'Dinner Table',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InviteShareSheet(
        sessionId: sessionId,
        roomCode: roomCode,
        sessionTitle: sessionTitle,
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text, String message) {
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    unawaited(HapticFeedback.lightImpact());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareInvite() async {
    final text = 'Join our dinner table "$sessionTitle" on Spliqo! '
        'Claim what you consume in real-time.\n'
        'Room code: $roomCode\n'
        'Link: $_inviteUrl';
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: 'Spliqo Dinner Invite: $sessionTitle',
      ),
    );
  }

  void _enterRoom(BuildContext context) {
    Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: AppRadius.roundedFull,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Title & Subtitle
            Text(
              'Invite Your Dining Friends',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Friends can scan the QR code or enter the code to claim items.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? AppColors.textMutedDark : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Table QR Code Card
            Center(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppRadius.roundedLg,
                  boxShadow: AppShadows.softCard,
                  border: Border.all(
                    color: AppColors.radiantViolet.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    QrImageView(
                      data: _inviteUrl,
                      size: 180,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF1E1B4B),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF1E1B4B),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Scan to join table',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Room Code Display Card
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.radiantViolet.withValues(alpha: 0.15)
                    : AppColors.radiantVioletSoft,
                borderRadius: AppRadius.roundedMd,
                border: Border.all(
                  color: AppColors.radiantViolet.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.tag_rounded,
                    color: AppColors.radiantViolet,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Room Code: $roomCode',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: AppColors.radiantViolet,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    color: AppColors.radiantViolet,
                    tooltip: 'Copy Room Code',
                    onPressed: () => _copyToClipboard(
                      context,
                      roomCode,
                      'Room code copied to clipboard!',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Share Actions Row
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copyToClipboard(
                      context,
                      _inviteUrl,
                      'Invite link copied to clipboard!',
                    ),
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Copy Link'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _shareInvite,
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // Go to Table Button
            ElevatedButton(
              onPressed: () => _enterRoom(context),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              ),
              child: const Text('Enter Live Room'),
            ),
          ],
        ),
      ),
    );
  }
}
