import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:spliqo/core/constants/app_tokens.dart';
import 'package:spliqo/core/theme/app_colors.dart';

/// Modal dialog allowing the host to visually inspect the uploaded physical receipt
/// with smooth pinch-to-zoom and pan.
class ReceiptPreviewDialog extends StatefulWidget {
  const new({
    required this.imageBytes,
    this.title = 'Receipt Inspection',
    super.key,
  });

  final Uint8List imageBytes;
  final String title;

  static Future<void> show(
    BuildContext context, {
    required Uint8List imageBytes,
    String title = 'Receipt Inspection',
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ReceiptPreviewDialog(
        imageBytes: imageBytes,
        title: title,
      ),
    );
  }

  @override
  State<ReceiptPreviewDialog> createState() => _ReceiptPreviewDialogState();
}

class _ReceiptPreviewDialogState extends State<ReceiptPreviewDialog> {
  final TransformationController _transformationController =
      TransformationController();

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog.fullscreen(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFF1E293B),
      child: SafeArea(
        child: Column(
          children: [
            // Top App Bar
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: 'Close Preview',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.restart_alt_rounded, color: Colors.white),
                    tooltip: 'Reset Zoom',
                    onPressed: _resetZoom,
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white24, height: 1),

            // Zoomable Image
            Expanded(
              child: Center(
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  maxScale: 6,
                  child: Image.memory(
                    widget.imageBytes,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Text(
                          'Could not render receipt preview.',
                          style: TextStyle(color: AppColors.errorRed),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // Bottom Tip Bar
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.sm,
                horizontal: AppSpacing.md,
              ),
              color: Colors.black26,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.pinch_rounded, size: 16, color: Colors.white70),
                  SizedBox(width: AppSpacing.xs),
                  Text(
                    'Pinch to zoom in on line items or taxes',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
