import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spliqo/core/utils/currency_formatter.dart';
import 'package:spliqo/core/utils/haptic_feedback_service.dart';
import 'package:spliqo/domain/models/payment_intent.dart';

/// Modal bottom sheet for resilient clipboard fallback when direct UPI app launching fails.
///
/// Features:
/// - One-tap copying of Host UPI ID, Exact Amount, and Full Intent URI.
/// - Clear step-by-step instructions for popular bank apps.
/// - Direct "I've Paid · Mark as Pending" action adhering to STANDARDS.md Section 11.4 & 11.5.
class UpiClipboardFallbackSheet extends StatelessWidget {
  const new({
    required this.intent,
    required this.onMarkPaid,
    super.key,
  });

  final PaymentIntentModel intent;
  final VoidCallback onMarkPaid;

  static Future<void> show(
    BuildContext context, {
    required PaymentIntentModel intent,
    required VoidCallback onMarkPaid,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => UpiClipboardFallbackSheet(
        intent: intent,
        onMarkPaid: onMarkPaid,
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    unawaited(HapticFeedbackService.lightImpact());
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'UPI App Not Available',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'No installed UPI app could open this payment intent. You can copy the payment URI string below to pay via your bank app:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),

              // Host UPI ID Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HOST UPI ID (VPA)',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          SelectableText(
                            intent.hostVpa,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _copyToClipboard(context, intent.hostVpa, 'UPI ID'),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy UPI ID'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Payable Amount Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EXACT AMOUNT (FINAL)',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            CurrencyFormatter.formatPaise(intent.amountPaise),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _copyToClipboard(
                        context,
                        intent.formattedAmount,
                        'Amount',
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy Amount'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Raw UPI Intent URI
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RAW INTENT URI',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      intent.upiUri,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Step-by-Step Instructions
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.amber),
                        SizedBox(width: 6),
                        Text(
                          'Banking Instructions',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildStep(1, 'Open GPay, PhonePe, Paytm, BHIM, CRED, or your bank app.'),
                    _buildStep(2, 'Select "Pay to UPI ID / VPA".'),
                    _buildStep(3, 'Paste the copied Host UPI ID & enter the exact amount.'),
                    _buildStep(4, 'Complete the payment, then tap "Mark as Paid" below.'),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copyToClipboard(
                        context,
                        intent.upiUri,
                        'Payment URI',
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy Intent'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onMarkPaid();
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Mark as Paid'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
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

  Widget _buildStep(int number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$number. ',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
