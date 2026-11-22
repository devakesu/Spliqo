import 'dart:async';

import 'package:flutter/material.dart';
import 'package:spliqo/core/utils/currency_formatter.dart';
import 'package:spliqo/core/utils/haptic_feedback_service.dart';
import 'package:spliqo/domain/models/session.dart';

/// Bill item tile allowing claim toggle with reactive claimant badges.
class BillItemTile extends StatelessWidget {
  const new({
    required this.item,
    required this.isClaimedByMe,
    required this.claimants,
    required this.onToggleClaim,
    this.isFrozen = false,
    super.key,
  });

  final BillItemModel item;
  final bool isClaimedByMe;
  final List<ParticipantModel> claimants;
  final VoidCallback onToggleClaim;
  final bool isFrozen;

  void _handleTap() {
    if (isFrozen) return;
    unawaited(HapticFeedbackService.selection());
    onToggleClaim();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isShared = claimants.length > 1;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: isClaimedByMe ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isClaimedByMe
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: isClaimedByMe ? 1.5 : 1,
        ),
      ),
      color: isClaimedByMe
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.2)
          : theme.colorScheme.surface,
      child: InkWell(
        onTap: isFrozen ? null : _handleTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: isClaimedByMe,
                    onChanged: isFrozen ? null : (_) => _handleTap(),
                    activeColor: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        if (isShared)
                          Text(
                            'Shared by ${claimants.length} participants (~${CurrencyFormatter.formatPaise(item.pricePaise ~/ claimants.length)} each)',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        CurrencyFormatter.formatPaise(item.pricePaise),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (isFrozen)
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock, size: 12, color: Colors.grey),
                            SizedBox(width: 2),
                            Text(
                              'Locked',
                              style: TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
              if (claimants.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: claimants.map((p) {
                      return Chip(
                        avatar: CircleAvatar(
                          backgroundColor: theme.colorScheme.primary,
                          child: Text(
                            p.displayName.isNotEmpty
                                ? p.displayName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                        label: Text(
                          p.displayName,
                          style: const TextStyle(fontSize: 11),
                        ),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
