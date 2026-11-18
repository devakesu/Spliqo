import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spliqo/core/utils/currency_formatter.dart';
import 'package:spliqo/domain/models/session.dart';
import 'package:spliqo/state/session_providers.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen 4: Immutable Final Shares & Settlement (Section 11 & 15.3 Standards)
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

  Future<void> _launchUpiIntent() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(paymentRepositoryProvider);
      final intentUriString = await repo.getPaymentIntent(widget.sessionId);
      final uri = Uri.parse(intentUriString);

      final canLaunch = await canLaunchUrl(uri);
      if (canLaunch) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          _showUpiFallbackDialog(intentUriString);
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

  void _showUpiFallbackDialog(String uriString) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('UPI App Not Available'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No installed UPI app could open this payment intent. You can copy the payment URI string below to pay via your bank app:',
              ),
              const SizedBox(height: 12),
              SelectableText(
                uriString,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                unawaited(Clipboard.setData(ClipboardData(text: uriString)));
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payment URI copied to clipboard')),
                );
              },
              child: const Text('Copy Intent'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markPaid() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Final Settlement'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(sessionRoomProvider(widget.sessionId).notifier).refresh(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Final status banner
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
                        'Total restaurant amount of ${CurrencyFormatter.formatPaise(session.totalPaise)} has been reconciled and settled.',
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
                    if (currentSettlement?.payPreference == PayPreference.selfPay) ...[
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
                        OutlinedButton(
                          onPressed: _isLoading ? null : _markPaid,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                          ),
                          child: const Text('Mark as Paid (Notify Host)'),
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
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...state.participants.map((p) {
            final s = state.settlements.cast<SettlementModel?>().firstWhere(
                  (item) => item?.participantId == p.id,
                  orElse: () => null,
                );
            final amountPaise = s?.finalAmountPaise ?? 0;
            final isSelf = p.id == currentParticipant?.id;

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
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
                                  style: const TextStyle(fontWeight: FontWeight.bold),
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
                          if (s?.payStatus == PayStatus.pending)
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
