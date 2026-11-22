import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spliqo/core/utils/currency_formatter.dart';
import 'package:spliqo/domain/models/session.dart';
import 'package:spliqo/presentation/screens/host_review_screen.dart';
import 'package:spliqo/presentation/screens/settlement_screen.dart';
import 'package:spliqo/presentation/widgets/bill_item_tile.dart';
import 'package:spliqo/presentation/widgets/connection_status_pill.dart';
import 'package:spliqo/presentation/widgets/estimated_share_footer.dart';
import 'package:spliqo/presentation/widgets/invite_share_sheet.dart';
import 'package:spliqo/presentation/widgets/participant_status_row.dart';
import 'package:spliqo/state/session_providers.dart';

/// Screen 2: Active Room & Item Selection (Model C Participant Experience)
class ActiveRoomScreen extends ConsumerWidget {
  const new({
    required this.sessionId,
    super.key,
  });

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionRoomProvider(sessionId));
    final notifier = ref.read(sessionRoomProvider(sessionId).notifier);
    final theme = Theme.of(context);

    // Auto-navigate to settlement if finalized
    if (state.session?.status == SessionStatus.finalized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => SettlementScreen(sessionId: sessionId),
          ),
        );
      });
    }

    if (state.isLoading && state.session == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Session Room')),
        body: Center(
          child: Text(state.errorMessage ?? 'Session not found.'),
        ),
      );
    }

    final session = state.session!;
    final isHost = state.isHost;
    final isReviewing = session.status == SessionStatus.reviewing;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.title, style: const TextStyle(fontSize: 16)),
            Row(
              children: [
                ConnectionStatusPill(
                  status: state.connectionStatus,
                  onRetry: notifier.refresh,
                ),
                const SizedBox(width: 8),
                Text(
                  isReviewing ? 'Reviewing Phase' : 'Live session',
                  style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_rounded),
            tooltip: 'Table QR & Invite Code',
            onPressed: () {
              unawaited(
                InviteShareSheet.show(
                  context,
                  sessionId: sessionId,
                  roomCode: sessionId.substring(0, 6).toUpperCase(),
                  sessionTitle: session.title,
                ),
              );
            },
          ),
          if (isHost && !isReviewing)
            IconButton(
              icon: const Icon(Icons.lock_clock_outlined),
              tooltip: 'Force Lock Room',
              onPressed: () => _showForceLockDialog(context, notifier),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: notifier.refresh,
          ),
          if (isHost && isReviewing)
            IconButton(
              icon: const Icon(Icons.rate_review_outlined),
              tooltip: 'Review & Finalise',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => HostReviewScreen(sessionId: sessionId),
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Banner for host during reviewing phase
          if (isHost && isReviewing)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.amber.shade100,
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'All participants finished! Proceed to resolve unallocated costs.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => HostReviewScreen(sessionId: sessionId),
                        ),
                      );
                    },
                    child: const Text('Review Bill'),
                  ),
                ],
              ),
            ),
          // Total restaurant bill header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      CurrencyFormatter.formatPaise(session.totalPaise),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Total restaurant bill · Paid by Host',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => _showParticipantsDialog(context, state, notifier),
                  icon: const Icon(Icons.people_outline, size: 18),
                  label: Text('${state.participants.length} Participants'),
                ),
              ],
            ),
          ),
          // Error bar if any
          if (state.errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.red.shade100,
              child: Text(
                state.errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          // Bill items list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: session.items.length,
              itemBuilder: (context, index) {
                final item = session.items[index];
                final isClaimed = state.isItemClaimedByMe(item.id);
                final claimants = state.getClaimantsForItem(item.id);

                return BillItemTile(
                  item: item,
                  isClaimedByMe: isClaimed,
                  claimants: claimants,
                  isFrozen: state.isSelectionCompleted || isReviewing,
                  onToggleClaim: () => notifier.toggleClaim(item.id),
                );
              },
            ),
          ),
          // Sticky bottom footer with live estimated share
          EstimatedShareFooter(
            estimatedSharePaise: state.estimatedSharePaise,
            isCompleted: state.isSelectionCompleted,
            isLoading: state.isLoading,
            onDoneSelecting: notifier.completeSelection,
          ),
        ],
      ),
    );
  }

  void _showParticipantsDialog(
    BuildContext context,
    SessionRoomState state,
    SessionRoomNotifier notifier,
  ) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (bottomSheetContext) {
          final hasIncomplete =
              state.participants.any((p) => !p.isSelectionCompleted);

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Participants',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: state.participants.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final p = state.participants[index];
                      final settlement = state.settlements
                          .cast<SettlementModel?>()
                          .firstWhere(
                            (s) => s?.participantId == p.id,
                            orElse: () => null,
                          );
                      final hasClaims =
                          state.claims.any((c) => c.participantId == p.id);

                      return ParticipantStatusRow(
                        participant: p,
                        settlement: settlement,
                        hasClaims: hasClaims,
                        isCurrentUser: p.id == state.currentParticipantId,
                      );
                    },
                  ),
                ),
                if (state.isHost &&
                    state.session?.status == SessionStatus.active &&
                    hasIncomplete) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(bottomSheetContext).pop();
                          _showForceLockDialog(context, notifier);
                        },
                        icon: const Icon(
                          Icons.lock_clock_outlined,
                          color: Colors.orange,
                        ),
                        label: const Text(
                          'Force Lock Room (Mark Inactive Done)',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange.shade900,
                          side: BorderSide(color: Colors.orange.shade300),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _showForceLockDialog(
    BuildContext context,
    SessionRoomNotifier notifier,
  ) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_outline, color: Colors.orange),
              SizedBox(width: 8),
              Text('Force Lock Room?'),
            ],
          ),
          content: const Text(
            'Any participants who have not tapped "Done Selecting" will be marked complete with their currently claimed items. The room will transition to the Reviewing phase (STANDARDS.md §3.3).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                unawaited(notifier.lockRoom());
              },
              child: const Text('Lock Room'),
            ),
          ],
        ),
      ),
    );
  }
}
