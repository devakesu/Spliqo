import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spliqo/core/utils/currency_formatter.dart';
import 'package:spliqo/domain/models/session.dart';
import 'package:spliqo/presentation/screens/settlement_screen.dart';
import 'package:spliqo/presentation/widgets/resolve_unclaimed_sheet.dart';
import 'package:spliqo/state/session_providers.dart';

/// Screen 3: Host Review & Finalisation Screen (Section 3.5 & 4.4 of Standards)
class HostReviewScreen extends ConsumerStatefulWidget {
  const new({
    required this.sessionId,
    super.key,
  });

  final String sessionId;

  @override
  ConsumerState<HostReviewScreen> createState() => _HostReviewScreenState();
}

class _HostReviewScreenState extends ConsumerState<HostReviewScreen> {
  bool _isFinalizing = false;
  bool _isReopening = false;
  String? _errorMessage;

  Future<void> _confirmReopenRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_open_rounded, color: Colors.blue),
            SizedBox(width: 8),
            Text('Reopen Room?'),
          ],
        ),
        content: const Text(
          'Reopening the room moves the session back to active selection and allows participants to modify their item claims (STANDARDS.md §3.3).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reopen Room'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _isReopening = true;
        _errorMessage = null;
      });
      try {
        final repo = ref.read(sessionRepositoryProvider);
        await repo.reopenRoom(widget.sessionId);
        await ref.read(sessionRoomProvider(widget.sessionId).notifier).refresh();
        if (mounted) {
          Navigator.of(context).pop();
        }
      } on Object catch (e) {
        if (mounted) {
          setState(() {
            _isReopening = false;
            _errorMessage = 'Could not reopen room: $e';
          });
        }
      }
    }
  }

  Future<void> _openResolveModal(
    List<BillItemModel> unclaimedItems,
    List<ParticipantModel> participants,
  ) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return ResolveUnclaimedSheet(
          unclaimedItems: unclaimedItems,
          participants: participants,
          onResolve: ({
            required action,
            targetParticipantId,
            itemIds,
          }) async {
            final repo = ref.read(sessionRepositoryProvider);
            await repo.resolveUnclaimed(
              sessionId: widget.sessionId,
              action: action,
              targetParticipantId: targetParticipantId,
              itemIds: itemIds,
            );
          },
        );
      },
    );

    if (result == true) {
      await ref.read(sessionRoomProvider(widget.sessionId).notifier).refresh();
    }
  }

  Future<void> _finalizeBill() async {
    setState(() {
      _isFinalizing = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(sessionRepositoryProvider);
      await repo.finalizeSession(widget.sessionId);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => SettlementScreen(sessionId: widget.sessionId),
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _isFinalizing = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sessionRoomProvider(widget.sessionId));
    final theme = Theme.of(context);

    if (state.isLoading && state.session == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final session = state.session;
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review Bill')),
        body: Center(child: Text(state.errorMessage ?? 'Session not found.')),
      );
    }

    // Determine unclaimed items
    final claimedItemIds = state.claims.map((c) => c.itemId).toSet();
    final unclaimedItems =
        session.items.where((i) => !claimedItemIds.contains(i.id)).toList();
    final hasUnclaimed = unclaimedItems.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Host Final Review'),
        actions: [
          TextButton.icon(
            onPressed: (_isFinalizing || _isReopening) ? null : _confirmReopenRoom,
            icon: const Icon(Icons.lock_open_rounded, size: 18),
            label: const Text('Reopen'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Session status summary
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        session.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Chip(
                        label: Text(session.status.name.toUpperCase()),
                        backgroundColor: hasUnclaimed
                            ? Colors.orange.shade100
                            : Colors.green.shade100,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Total Bill: ${CurrencyFormatter.formatPaise(session.totalPaise)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Unclaimed items banner / action
          if (hasUnclaimed) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.amber),
                      const SizedBox(width: 8),
                      Text(
                        'Unresolved Items (${unclaimedItems.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.brown,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'You cannot finalise the bill until all items are allocated. Choose how to distribute them.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _openResolveModal(
                      unclaimedItems,
                      state.participants,
                    ),
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Resolve Unclaimed Items'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Allocation preview per participant
          Text(
            'Participant Allocation Preview',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...state.participants.map((p) {
            final participantItemIds = state.claims
                .where((c) => c.participantId == p.id)
                .map((c) => c.itemId)
                .toSet();
            final participantItems =
                session.items.where((i) => participantItemIds.contains(i.id)).toList();

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: p.role == ParticipantRole.host
                      ? Colors.amber.shade700
                      : Colors.indigo,
                  child: Text(
                    p.displayName.isNotEmpty ? p.displayName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(p.displayName),
                subtitle: Text('${participantItems.length} items claimed'),
                trailing: Text(
                  p.isSelectionCompleted ? 'Ready' : 'Selecting',
                  style: TextStyle(
                    color: p.isSelectionCompleted ? Colors.green : Colors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          // Consolidated adjustments breakdown
          Card(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bill Reconciliation',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildRow('Subtotal', session.subtotalPaise),
                  _buildRow('Tax / GST', session.taxPaise),
                  _buildRow('Service Charge', session.serviceChargePaise),
                  _buildRow('Discount', -session.discountPaise),
                  _buildRow('Round Off', session.roundOffPaise),
                  const Divider(),
                  _buildRow('Final Payable Total', session.totalPaise, isBold: true),
                ],
              ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          // Authoritative Finalisation CTA
          ElevatedButton(
            onPressed: (_isFinalizing || hasUnclaimed) ? null : _finalizeBill,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
            child: _isFinalizing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Finalise Bill & Generate Shares',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, int amountPaise, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
          ),
          Text(
            CurrencyFormatter.formatPaise(amountPaise),
            style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
          ),
        ],
      ),
    );
  }
}
