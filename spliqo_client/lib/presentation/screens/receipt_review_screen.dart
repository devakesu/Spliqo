import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spliqo/core/utils/currency_formatter.dart';
import 'package:spliqo/domain/models/session.dart';
import 'package:spliqo/presentation/screens/active_room_screen.dart';
import 'package:spliqo/state/session_providers.dart';

/// Screen 1: Host Receipt Ingestion & Draft Review (Section 3.1 & 10.5 of Standards)
/// Displays extracted line items, reconciles adjustments, and allows activation.
class ReceiptReviewScreen extends ConsumerStatefulWidget {
  const new({
    this.initialSession,
    super.key,
  });

  final SessionModel? initialSession;

  @override
  ConsumerState<ReceiptReviewScreen> createState() => _ReceiptReviewScreenState();
}

class _ReceiptReviewScreenState extends ConsumerState<ReceiptReviewScreen> {
  SessionModel? _session;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
  }

  Future<void> _mockUploadAndParse() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(sessionRepositoryProvider);
      // Construct a valid test image byte stream with JPEG magic bytes
      final jpegBytes = [
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00,
        ...List.filled(100, 0),
      ];

      final parseResp = await repo.parseReceipt(
        imageBytes: jpegBytes,
        filename: 'receipt.jpg',
        hostDisplayName: 'Host',
      );

      final sessionData = parseResp['session'] as Map<String, dynamic>;
      setState(() {
        _session = SessionModel.fromJson(sessionData);
        _isLoading = false;
      });
    } on Exception catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Receipt parse failed: $e';
      });
    }
  }

  Future<void> _activateSession() async {
    if (_session == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(sessionRepositoryProvider);
      final activeSession = await repo.activateSession(_session!.id);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => ActiveRoomScreen(sessionId: activeSession.id),
          ),
        );
      }
    } on Exception catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to activate session: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt Draft Review'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _session == null
              ? _buildEmptyState(theme)
              : _buildReviewContent(theme),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'No Receipt Loaded',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload a receipt image to automatically extract items, or proceed with sample receipt.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _mockUploadAndParse,
              icon: const Icon(Icons.document_scanner),
              label: const Text('Parse Receipt (Gemini Vision)'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReviewContent(ThemeData theme) {
    final session = _session!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Chip(
                      label: Text(session.status.name.toUpperCase()),
                      backgroundColor: Colors.amber.shade100,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Please review all line items and totals before activating the room for participants.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Line Items (${session.items.length})',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...session.items.map((item) {
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                radius: 14,
                child: Text('${item.position + 1}'),
              ),
              title: Text(item.name),
              trailing: Text(
                CurrencyFormatter.formatPaise(item.pricePaise),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
        Card(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildSummaryRow('Subtotal', session.subtotalPaise),
                if (session.taxPaise > 0)
                  _buildSummaryRow('Tax / GST', session.taxPaise),
                if (session.serviceChargePaise > 0)
                  _buildSummaryRow('Service Charge', session.serviceChargePaise),
                if (session.discountPaise > 0)
                  _buildSummaryRow('Discount', -session.discountPaise),
                if (session.roundOffPaise != 0)
                  _buildSummaryRow('Round Off', session.roundOffPaise),
                const Divider(),
                _buildSummaryRow('Total Bill', session.totalPaise, isBold: true),
              ],
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _isLoading ? null : _activateSession,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
          ),
          child: const Text(
            'Activate Session & Invite Participants',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, int amountPaise, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: isBold ? 16 : 14,
            ),
          ),
          Text(
            CurrencyFormatter.formatPaise(amountPaise),
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: isBold ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }
}
