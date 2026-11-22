import 'dart:async';

import 'package:flutter/material.dart';
import 'package:spliqo/core/utils/currency_formatter.dart';
import 'package:spliqo/core/utils/haptic_feedback_service.dart';
import 'package:spliqo/domain/models/session.dart';

/// Modal bottom sheet for host resolution of unclaimed items (Section 3.5 of Standards).
///
/// Features:
/// - Visual breakdown checklist of unclaimed items.
/// - Cherry-pick specific items or resolve all at once.
/// - Three interactive resolution actions:
///   1. Split equally among all participants
///   2. Assign to specific participant
///   3. Host absorbs
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
  late Set<String> _selectedItemIds;
  String? _selectedParticipantId;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Default to all unclaimed items selected
    _selectedItemIds = widget.unclaimedItems.map((i) => i.id).toSet();
    if (widget.participants.isNotEmpty) {
      _selectedParticipantId = widget.participants.first.id;
    }
  }

  int get _selectedTotalPaise => widget.unclaimedItems
      .where((i) => _selectedItemIds.contains(i.id))
      .fold(0, (sum, i) => sum + i.pricePaise);

  void _toggleSelectAll() {
    setState(() {
      if (_selectedItemIds.length == widget.unclaimedItems.length) {
        _selectedItemIds.clear();
      } else {
        _selectedItemIds = widget.unclaimedItems.map((i) => i.id).toSet();
      }
    });
  }

  Future<void> _submit(String action) async {
    if (_selectedItemIds.isEmpty) {
      setState(() {
        _errorMessage = 'Please select at least one item to resolve.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    unawaited(HapticFeedbackService.impact());

    try {
      await widget.onResolve(
        action: action,
        targetParticipantId: _selectedParticipantId,
        itemIds: _selectedItemIds.toList(),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object catch (e) {
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
    final allSelected =
        _selectedItemIds.length == widget.unclaimedItems.length &&
            widget.unclaimedItems.isNotEmpty;
    final participantCount =
        widget.participants.isEmpty ? 1 : widget.participants.length;
    final perPersonSplitPaise = _selectedTotalPaise ~/ participantCount;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Sheet grab handle
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
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text(
                      'Unresolved Items (${widget.unclaimedItems.length})',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _isSubmitting ? null : _toggleSelectAll,
                  child: Text(allSelected ? 'Deselect All' : 'Select All'),
                ),
              ],
            ),
            Text(
              'Selected: ${_selectedItemIds.length} items (${CurrencyFormatter.formatPaise(_selectedTotalPaise)})',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 8),
            // Scrollable Item checklist
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.unclaimedItems.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = widget.unclaimedItems[index];
                  final isChecked = _selectedItemIds.contains(item.id);

                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      item.name,
                      style: TextStyle(
                        fontWeight:
                            isChecked ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(CurrencyFormatter.formatPaise(item.pricePaise)),
                    value: isChecked,
                    onChanged: _isSubmitting
                        ? null
                        : (val) {
                            setState(() {
                              if (val == true) {
                                _selectedItemIds.add(item.id);
                              } else {
                                _selectedItemIds.remove(item.id);
                              }
                            });
                          },
                  );
                },
              ),
            ),
            const Divider(height: 16),
            // Actions Section
            Text(
              'Choose Allocation Action',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            // 1. Split equally among all participants
            Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.call_split, color: Colors.blue),
                title: const Text(
                  'Split Among All Participants',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Divides ${CurrencyFormatter.formatPaise(_selectedTotalPaise)} equally (~${CurrencyFormatter.formatPaise(perPersonSplitPaise)} each for $participantCount people)',
                ),
                trailing: _isSubmitting
                    ? null
                    : const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: _isSubmitting || _selectedItemIds.isEmpty
                    ? null
                    : () => _submit('split_all'),
              ),
            ),
            const SizedBox(height: 8),
            // 2. Host absorbs
            Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.teal.withValues(alpha: 0.3)),
              ),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.shield_outlined, color: Colors.teal),
                title: const Text(
                  'Host Absorbs Unclaimed',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Host covers ${CurrencyFormatter.formatPaise(_selectedTotalPaise)} directly.',
                ),
                trailing: _isSubmitting
                    ? null
                    : const Icon(Icons.arrow_forward_ios, size: 14),
                onTap: _isSubmitting || _selectedItemIds.isEmpty
                    ? null
                    : () => _submit('host_absorb'),
              ),
            ),
            const SizedBox(height: 8),
            // 3. Assign to specific person
            if (widget.participants.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  isDense: true,
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
                const SizedBox(height: 6),
                ElevatedButton(
                  onPressed: _isSubmitting || _selectedItemIds.isEmpty
                      ? null
                      : () => _submit('assign_to_participant'),
                  child: const Text('Confirm Assignment to Participant'),
                ),
              ],
            ],
            if (_isSubmitting) ...[
              const SizedBox(height: 12),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    ),
  );
}
}
