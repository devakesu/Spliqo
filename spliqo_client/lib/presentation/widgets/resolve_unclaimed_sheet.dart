import 'package:flutter/material.dart';
import 'package:spliqo/core/utils/currency_formatter.dart';
import 'package:spliqo/domain/models/session.dart';

/// Modal bottom sheet for host resolution of unclaimed items (Section 3.5 of Standards).
class ResolveUnclaimedSheet extends StatefulWidget {
  const new({
    required this.unclaimedItems,
    required this.participants,
    required this.onResolve,
    super.key,
  });

  final List<BillItemModel> unclaimedItems;
  final List<ParticipantModel> participants;
  final Future<void> Function({
    required String action,
    String? targetParticipantId,
    List<String>? itemIds,
  }) onResolve;

  @override
  State<ResolveUnclaimedSheet> createState() => _ResolveUnclaimedSheetState();
}

class _ResolveUnclaimedSheetState extends State<ResolveUnclaimedSheet> {
  String? _selectedParticipantId;
  bool _isSubmitting = false;
  String? _errorMessage;

  int get totalUnclaimedPaise =>
      widget.unclaimedItems.fold(0, (sum, i) => sum + i.pricePaise);

  Future<void> _submit(String action) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.onResolve(
        action: action,
        targetParticipantId: _selectedParticipantId,
        itemIds: widget.unclaimedItems.map((i) => i.id).toList(),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Resolve Unclaimed Items (${widget.unclaimedItems.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Total unclaimed amount: ${CurrencyFormatter.formatPaise(totalUnclaimedPaise)}. All items must be assigned before the bill can be finalised.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.call_split, color: Colors.blue),
              title: const Text('Split Among All Participants'),
              subtitle: Text(
                'Divides remaining items equally across all ${widget.participants.length} people.',
              ),
              trailing: _isSubmitting
                  ? null
                  : const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: _isSubmitting ? null : () => _submit('split_all'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.3),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.shield_outlined, color: Colors.teal),
              title: const Text('Host Absorbs Unclaimed'),
              subtitle: const Text('Assign all unallocated items to host.'),
              trailing: _isSubmitting
                  ? null
                  : const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: _isSubmitting ? null : () => _submit('host_absorb'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.3),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (widget.participants.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Assign to specific participant',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                initialValue: _selectedParticipantId,
                items: widget.participants.map((p) {
                  return DropdownMenuItem(
                    value: p.id,
                    child: Text(p.displayName),
                  );
                }).toList(),
                onChanged: _isSubmitting
                    ? null
                    : (val) {
                        setState(() {
                          _selectedParticipantId = val;
                        });
                      },
              ),
              if (_selectedParticipantId != null) ...[
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => _submit('assign_to_participant'),
                  child: const Text('Confirm Assignment'),
                ),
              ],
            ],
            if (_isSubmitting) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
