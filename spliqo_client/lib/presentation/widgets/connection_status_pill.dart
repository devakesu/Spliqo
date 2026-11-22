import 'package:flutter/material.dart';

/// Connection states for real-time room synchronization.
enum RealtimeConnectionStatus {
  live,
  reconnecting,
  offline,
}

/// Visual pill widget displaying the table's real-time sync connectivity.
class ConnectionStatusPill extends StatelessWidget {
  const new({
    this.status = RealtimeConnectionStatus.live,
    this.onRetry,
    super.key,
  });

  final RealtimeConnectionStatus status;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Color dotColor;
    final Color bgColor;
    final Color textColor;
    final String label;
    final IconData? actionIcon;

    switch (status) {
      case RealtimeConnectionStatus.live:
        dotColor = Colors.green;
        bgColor = Colors.green.withValues(alpha: 0.12);
        textColor = Colors.green.shade800;
        label = 'Live Sync';
        actionIcon = null;
      case RealtimeConnectionStatus.reconnecting:
        dotColor = Colors.amber.shade700;
        bgColor = Colors.amber.withValues(alpha: 0.15);
        textColor = Colors.amber.shade900;
        label = 'Reconnecting...';
        actionIcon = null;
      case RealtimeConnectionStatus.offline:
        dotColor = Colors.red.shade700;
        bgColor = Colors.red.withValues(alpha: 0.15);
        textColor = Colors.red.shade900;
        label = 'Offline';
        actionIcon = Icons.refresh_rounded;
    }

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dotColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (actionIcon != null) ...[
            const SizedBox(width: 4),
            Icon(actionIcon, size: 12, color: textColor),
          ],
        ],
      ),
    );

    if (status == RealtimeConnectionStatus.offline && onRetry != null) {
      return InkWell(
        onTap: onRetry,
        borderRadius: BorderRadius.circular(20),
        child: content,
      );
    }

    return content;
  }
}
