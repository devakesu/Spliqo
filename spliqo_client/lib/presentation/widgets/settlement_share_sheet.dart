import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:spliqo/core/utils/currency_formatter.dart';
import 'package:spliqo/core/utils/haptic_feedback_service.dart';
import 'package:spliqo/domain/models/session.dart';

/// Modal bottom sheet for sharing and exporting the final settlement breakdown.
///
/// Features:
/// - Formatted summary for WhatsApp and messaging apps.
/// - Native OS share sheet integration via SharePlus.
/// - One-tap copy to clipboard.
class SettlementShareSheet extends StatelessWidget {
  const new({
    required this.session,
    required this.participants,
    required this.settlements,
    super.key,
  });

  final SessionModel session;
  final List<ParticipantModel> participants;
  final List<SettlementModel> settlements;

  static Future<void> show(
    BuildContext context, {
    required SessionModel session,
    required List<ParticipantModel> participants,
    required List<SettlementModel> settlements,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SettlementShareSheet(
        session: session,
        participants: participants,
        settlements: settlements,
      ),
    );
  }

  String _generateSummaryText() {
    final buffer = StringBuffer()
      ..writeln('🧾 *Spliqo Bill Settlement*')
      ..writeln('📍 *${session.title}*')
      ..writeln('💵 Total Bill: ${CurrencyFormatter.formatPaise(session.totalPaise)}');

    final hostParticipant = participants.cast<ParticipantModel?>().firstWhere(
          (p) => p?.role == ParticipantRole.host,
          orElse: () => null,
        );
    if (hostParticipant != null) {
      buffer.writeln('👑 Host: ${hostParticipant.displayName}');
    }

    buffer
      ..writeln()
      ..writeln('👥 *Individual Shares (Final):*');

    var settledCount = 0;
    var collectedPaise = 0;

    for (final p in participants) {
      final s = settlements.cast<SettlementModel?>().firstWhere(
            (item) => item?.participantId == p.id,
            orElse: () => null,
          );

      final isHost = p.role == ParticipantRole.host;
      final amountPaise = isHost
          ? (session.totalPaise -
              settlements.fold<int>(
                0,
                (sum, st) =>
                    st.participantId != p.id ? sum + (st.finalAmountPaise ?? 0) : sum,
              ))
          : (s?.finalAmountPaise ?? 0);

      final isSettled = isHost ||
          s?.payStatus == PayStatus.paid ||
          s?.payStatus == PayStatus.waived;

      if (isSettled) {
        settledCount++;
        collectedPaise += amountPaise;
      }

      final String statusTag;
      if (isHost) {
        statusTag = '[Host · Paid Bill]';
      } else if (s?.payStatus == PayStatus.paid) {
        statusTag = '[Paid ✓]';
      } else if (s?.payStatus == PayStatus.waived) {
        statusTag = '[Covered by Host]';
      } else if (s?.payStatus == PayStatus.pending) {
        statusTag = '[Pending Host Confirmation]';
      } else if (s?.payPreference == PayPreference.hostPays) {
        statusTag = '[Host Cover Requested]';
      } else {
        statusTag = '[Unpaid]';
      }

      buffer.writeln('• ${p.displayName}: ${CurrencyFormatter.formatPaise(amountPaise)} $statusTag');
    }

    buffer
      ..writeln()
      ..writeln(
        '📊 *Progress:* $settledCount of ${participants.length} settled (${CurrencyFormatter.formatPaise(collectedPaise)} / ${CurrencyFormatter.formatPaise(session.totalPaise)})',
      )
      ..writeln('✨ Coordinated with Spliqo');

    return buffer.toString();
  }

  Future<void> _shareViaApp(BuildContext context) async {
    unawaited(HapticFeedbackService.impact());
    final text = _generateSummaryText();
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: 'Settlement for ${session.title}',
      ),
    );
  }

  void _copyToClipboard(BuildContext context) {
    unawaited(HapticFeedbackService.lightImpact());
    final text = _generateSummaryText();
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settlement breakdown copied to clipboard'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summaryText = _generateSummaryText();

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grab handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.receipt_long_rounded, color: Colors.indigo),
                      const SizedBox(width: 8),
                      Text(
                        'Share Settlement Breakdown',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Visual preview card
              Container(
                constraints: const BoxConstraints(maxHeight: 280),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    summaryText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Share & Copy Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copyToClipboard(context),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy Text'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => _shareViaApp(context),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('Share to WhatsApp / Apps'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
