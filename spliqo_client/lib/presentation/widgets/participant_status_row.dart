import 'package:flutter/material.dart';
import 'package:spliqo/domain/models/session.dart';

/// Row rendering an individual participant with badges for the 3 independent states:
/// 1. Item Selection (Pending / Selecting / Completed)
/// 2. Payment Preference (Undecided / Self-pay / Host-pays)
/// 3. Payment Status (Unpaid / Pending / Paid / Waived)
class ParticipantStatusRow extends StatelessWidget {
  const new({
    required this.participant,
    this.settlement,
    this.hasClaims = false,
    this.isCurrentUser = false,
    super.key,
  });

  final ParticipantModel participant;
  final SettlementModel? settlement;
  final bool hasClaims;
  final bool isCurrentUser;

  Widget _buildSelectionBadge() {
    if (participant.isSelectionCompleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 12, color: Colors.green),
            SizedBox(width: 4),
            Text(
              'Completed',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.green,
              ),
            ),
          ],
        ),
      );
    }

    if (hasClaims) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit, size: 12, color: Colors.blue),
            SizedBox(width: 4),
            Text(
              'Selecting',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.blue,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Not started',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget? _buildPaymentBadge() {
    if (settlement == null) {
      return null;
    }

    final payStatus = settlement!.payStatus;
    Color color;
    IconData icon;
    String text;

    switch (payStatus) {
      case PayStatus.paid:
        color = Colors.green;
        icon = Icons.check_circle;
        text = 'Paid';
      case PayStatus.waived:
        color = Colors.purple;
        icon = Icons.handshake;
        text = 'Waived';
      case PayStatus.pending:
        color = Colors.orange;
        icon = Icons.hourglass_top;
        text = 'Pending Confirmation';
      case PayStatus.unpaid:
        color = Colors.red;
        icon = Icons.pending;
        text = settlement!.payPreference == PayPreference.hostPays
            ? 'Host requested'
            : 'Unpaid';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isHost = participant.role == ParticipantRole.host;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isHost ? Colors.amber.shade700 : Colors.indigo,
            child: Text(
              participant.displayName.isNotEmpty
                  ? participant.displayName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      participant.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (isCurrentUser)
                      const Text(
                        ' (You)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    if (isHost)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Host',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                  ],
                ),
                if (settlement != null &&
                    settlement!.payPreference != PayPreference.undecided)
                  Text(
                    settlement!.payPreference == PayPreference.selfPay
                        ? 'Preference: Self-pay'
                        : 'Preference: Host pays',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildSelectionBadge(),
              if (_buildPaymentBadge() != null) ...[
                const SizedBox(height: 4),
                _buildPaymentBadge()!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}
