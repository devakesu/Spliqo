import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spliqo/core/utils/currency_formatter.dart';
import 'package:spliqo/core/utils/haptic_feedback_service.dart';
import 'package:spliqo/domain/models/session.dart';
import 'package:spliqo/presentation/widgets/settlement_share_sheet.dart';
import 'package:spliqo/presentation/widgets/upi_clipboard_fallback_sheet.dart';
import 'package:spliqo/state/session_providers.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen 4: Immutable Final Shares & Settlement (Section 11 & 15.3 Standards)
///
/// Features:
/// - Server-assembled UPI intent handoff via upi://pay.
/// - Resilient clipboard fallback sheet with 1-tap copy and banking instructions.
/// - Host real-time settlement confirmation, rejection, and waive actions.
/// - Settlement progress counter and celebratory banner when all shares are settled.
/// - Shareable settlement breakdown export for messaging apps.
class SettlementScreen extends ConsumerStatefulWidget {
  const new({
    required this.sessionId,
    super.key,
  });

  final String sessionId;

  @override
  ConsumerState<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends ConsumerState<SettlementScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _updatePreference(PayPreference preference) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(paymentRepositoryProvider);
      await repo.updatePaymentPreference(
        sessionId: widget.sessionId,
        preference: preference,
      );
      await ref.read(sessionRoomProvider(widget.sessionId).notifier).refresh();
      setState(() => _isLoading = false);
    } on Exception catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not update payment preference: $e';
      });
    }
  }

  Future<void> _launchUpiIntent({bool forceFallback = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(paymentRepositoryProvider);
      final intent = await repo.getPaymentIntent(widget.sessionId);

      if (forceFallback) {
        if (mounted) {
          unawaited(
            UpiClipboardFallbackSheet.show(
              context,
              intent: intent,
              onMarkPaid: _markPaid,
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      final uri = Uri.parse(intent.upiUri);
      final canLaunch = await canLaunchUrl(uri);
      if (canLaunch) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          unawaited(
            UpiClipboardFallbackSheet.show(
              context,
              intent: intent,
              onMarkPaid: _markPaid,
            ),
          );
        }
      }
      setState(() => _isLoading = false);
    } on Exception catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not launch UPI intent: $e';
      });
    }
  }

  Future<void> _markPaid() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    unawaited(HapticFeedbackService.impact());

    try {
      final repo = ref.read(paymentRepositoryProvider);
      await repo.markPaymentPending(widget.sessionId);
      await ref.read(sessionRoomProvider(widget.sessionId).notifier).refresh();
      setState(() => _isLoading = false);
    } on Exception catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not mark payment as pending: $e';
      });
    }
  }

  Future<void> _hostConfirm(String participantId, String action) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    unawaited(HapticFeedbackService.impact());

    try {
      final repo = ref.read(paymentRepositoryProvider);
      await repo.confirmPayment(
        sessionId: widget.sessionId,
        targetParticipantId: participantId,
        action: action,
      );
      await ref.read(sessionRoomProvider(widget.sessionId).notifier).refresh();
      setState(() => _isLoading = false);
    } on Exception catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Host action failed: $e';
      });
    }
  }

  Future<void> _showRejectDialog(String participantId, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Reject Payment?'),
          ],
        ),
        content: Text(
          'Mark $displayName back to Unpaid? Use this if funds did not arrive in your bank account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reject to Unpaid'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _hostConfirm(participantId, 'reject_unpaid');
    }
  }

  void _openShareSheet(
    SessionModel session,
    List<ParticipantModel> participants,
    List<SettlementModel> settlements,
  ) {
    unawaited(
      SettlementShareSheet.show(
        context,
        session: session,
        participants: participants,
        settlements: settlements,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sessionRoomProvider(widget.sessionId));
    final theme = Theme.of(context);

    if (state.isLoading && state.session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final session = state.session;
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settlement')),
        body: Center(child: Text(state.errorMessage ?? 'Session not found.')),
      );
    }

    final currentParticipant = state.currentParticipant;
    final currentSettlement = state.currentSettlement;
    final isHost = state.isHost;
    final myFinalAmountPaise = currentSettlement?.finalAmountPaise ?? 0;

    // Calculate settlement progress
    final totalParticipants = state.participants.length;
    var settledCount = 0;
    for (final p in state.participants) {
      if (p.role == ParticipantRole.host) {
        settledCount++;
      } else {
        final s = state.settlements.cast<SettlementModel?>().firstWhere(
              (item) => item?.participantId == p.id,
              orElse: () => null,
            );
        if (s?.payStatus == PayStatus.paid || s?.payStatus == PayStatus.waived) {
          settledCount++;
        }
      }
    }
    final allSettled =
        settledCount == totalParticipants && totalParticipants > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Final Settlement'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share Breakdown',
            onPressed: () => _openShareSheet(
              session,
              state.participants,
              state.settlements,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () =>
                ref.read(sessionRoomProvider(widget.sessionId).notifier).refresh(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Celebratory Banner or Bill Finalised Status Banner
          if (allSettled)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.celebration_rounded,
                        color: Colors.green,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'All Shares Settled! 🎉',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Every participant has completed their share. The dining session is fully settled.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _openShareSheet(
                      session,
                      state.participants,
                      state.settlements,
                    ),
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text('Export & Share Breakdown'),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified, color: Colors.green, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bill Finalised',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        Text(
                          'Total restaurant amount of ${CurrencyFormatter.formatPaise(session.totalPaise)} has been reconciled and settled. ($settledCount of $totalParticipants settled)',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),

          // Participant's Final Share Card
          if (!isHost && currentParticipant != null) ...[
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'YOUR FINAL SHARE',
                          style: theme.textTheme.labelMedium?.copyWith(
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Final',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      CurrencyFormatter.formatPaise(myFinalAmountPaise),
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const Divider(height: 24),
                    // Payment Preference Selection
                    Text(
                      'Choose Payment Method:',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Pay my share'),
                            selected: currentSettlement?.payPreference ==
                                PayPreference.selfPay,
                            onSelected: _isLoading
                                ? null
                                : (sel) {
                                    if (sel) {
                                      unawaited(
                                        _updatePreference(
                                          PayPreference.selfPay,
                                        ),
                                      );
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Let host cover'),
                            selected: currentSettlement?.payPreference ==
                                PayPreference.hostPays,
                            onSelected: _isLoading
                                ? null
                                : (sel) {
                                    if (sel) {
                                      unawaited(
                                        _updatePreference(
                                          PayPreference.hostPays,
                                        ),
                                      );
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Action according to preference and status
                    if (currentSettlement?.payPreference ==
                        PayPreference.selfPay) ...[
                      if (currentSettlement?.payStatus == PayStatus.unpaid) ...[
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _launchUpiIntent,
                          icon: const Icon(Icons.payment),
                          label: const Text('Pay with UPI App'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isLoading
                                    ? null
                                    : () => _launchUpiIntent(forceFallback: true),
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                label: const Text('Copy UPI Details'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _isLoading ? null : _markPaid,
                                child: const Text('Mark as Paid (Notify Host)'),
                              ),
                            ),
                          ],
                        ),
                      ] else if (currentSettlement?.payStatus ==
                          PayStatus.pending) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.hourglass_top, color: Colors.orange),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Waiting for host to confirm your payment.',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (currentSettlement?.payStatus ==
                          PayStatus.paid) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green),
                              SizedBox(width: 8),
                              Text(
                                'Payment confirmed by host!',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ] else if (currentSettlement?.payPreference ==
                        PayPreference.hostPays) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          currentSettlement?.payStatus == PayStatus.waived
                              ? 'Host has covered your share!'
                              : 'Requested host to cover your share. Awaiting host confirmation.',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Host Management View: All Participant Shares & Confirmation
          Text(
            isHost ? 'Participant Settlements & Actions' : 'All Participant Shares',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...state.participants.map((p) {
            final s = state.settlements.cast<SettlementModel?>().firstWhere(
                  (item) => item?.participantId == p.id,
                  orElse: () => null,
                );
            final amountPaise = s?.finalAmountPaise ?? 0;
            final isSelf = p.id == currentParticipant?.id;
            final isPending = s?.payStatus == PayStatus.pending;

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isPending
                      ? Colors.orange.shade300
                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: isPending ? 1.5 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: p.role == ParticipantRole.host
                                  ? Colors.amber.shade700
                                  : Colors.indigo,
                              child: Text(
                                p.displayName.isNotEmpty
                                    ? p.displayName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.displayName + (isSelf ? ' (You)' : ''),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  s?.payPreference == PayPreference.hostPays
                                      ? 'Host covers'
                                      : 'Self-pay',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              CurrencyFormatter.formatPaise(amountPaise),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              s?.payStatus.name.toUpperCase() ?? 'UNPAID',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: s?.payStatus == PayStatus.paid ||
                                        s?.payStatus == PayStatus.waived
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Host Action Buttons
                    if (isHost && p.role != ParticipantRole.host) ...[
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (isPending) ...[
                            OutlinedButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : () => _showRejectDialog(p.id, p.displayName),
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: Colors.red,
                              ),
                              label: const Text(
                                'Reject',
                                style: TextStyle(color: Colors.red),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.red),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : () => _hostConfirm(p.id, 'confirm_paid'),
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Confirm Paid'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                          if (s?.payPreference == PayPreference.hostPays &&
                              s?.payStatus != PayStatus.waived) ...[
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : () => _hostConfirm(p.id, 'confirm_waived'),
                              icon: const Icon(Icons.handshake, size: 16),
                              label: const Text('Waive Share'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }
}
