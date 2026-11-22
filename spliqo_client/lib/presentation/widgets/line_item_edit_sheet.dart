import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spliqo/core/constants/app_tokens.dart';
import 'package:spliqo/core/theme/app_colors.dart';
import 'package:spliqo/domain/allocation/allocation.dart';
import 'package:spliqo/domain/models/session.dart';

enum LineItemEditAction { save, split, delete }

class LineItemEditResult {
  const new save(this.item)
      : action = LineItemEditAction.save,
        splitItems = null;

  const new split(this.splitItems)
      : action = LineItemEditAction.split,
        item = null;

  const new delete()
      : action = LineItemEditAction.delete,
        item = null,
        splitItems = null;

  final LineItemEditAction action;
  final BillItemModel? item;
  final List<BillItemModel>? splitItems;
}

/// Modal bottom sheet allowing host to rename items, adjust price in integer paise,
/// split items equally without float drift, or remove misread OCR items.
class LineItemEditSheet extends StatefulWidget {
  const new({
    this.initialItem,
    this.nextPosition = 0,
    super.key,
  });

  final BillItemModel? initialItem;
  final int nextPosition;

  static Future<LineItemEditResult?> show(
    BuildContext context, {
    BillItemModel? initialItem,
    int nextPosition = 0,
  }) {
    return showModalBottomSheet<LineItemEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LineItemEditSheet(
        initialItem: initialItem,
        nextPosition: nextPosition,
      ),
    );
  }

  @override
  State<LineItemEditSheet> createState() => _LineItemEditSheetState();
}

class _LineItemEditSheetState extends State<LineItemEditSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  int _splitCount = 2;
  String? _error;

  bool get _isEditing => widget.initialItem != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialItem?.name ?? '',
    );
    final initialPaise = widget.initialItem?.pricePaise;
    _priceController = TextEditingController(
      text: initialPaise != null
          ? (initialPaise / 100).toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  int? _parsePaiseFromInput(String raw) {
    final clean = raw.trim().replaceAll(',', '');
    if (clean.isEmpty) return null;

    final parts = clean.split('.');
    if (parts.length > 2) return null;

    final rupees = int.tryParse(parts[0]) ?? 0;
    if (rupees < 0) return null;

    var paise = 0;
    if (parts.length == 2) {
      final pStr = parts[1].padRight(2, '0');
      if (pStr.length > 2) {
        paise = int.tryParse(pStr.substring(0, 2)) ?? 0;
      } else {
        paise = int.tryParse(pStr) ?? 0;
      }
    }

    final total = (rupees * 100) + paise;
    if (total <= 0 || total > 10000000) return null;
    return total;
  }

  void _handleSave() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter an item name.');
      return;
    }

    final pricePaise = _parsePaiseFromInput(_priceController.text);
    if (pricePaise == null) {
      setState(() => _error = 'Please enter a valid price (₹1 - ₹1,00,000).');
      return;
    }

    final item = BillItemModel(
      id: widget.initialItem?.id ?? 'temp_${DateTime.now().millisecondsSinceEpoch}',
      sessionId: widget.initialItem?.sessionId ?? 'draft_session',
      name: name,
      pricePaise: pricePaise,
      position: widget.initialItem?.position ?? widget.nextPosition,
    );

    Navigator.of(context).pop(LineItemEditResult.save(item));
  }

  void _handleSplit() {
    final name = _nameController.text.trim();
    final pricePaise = _parsePaiseFromInput(_priceController.text);

    if (name.isEmpty || pricePaise == null) {
      setState(() => _error = 'Valid name and price required to split.');
      return;
    }

    // Split exact paise using Largest Remainder Engine
    final weights = <String, int>{
      for (var i = 0; i < _splitCount; i++) 'p$i': 1,
    };
    final sharesMap = splitExact(pricePaise, weights);

    final basePos = widget.initialItem?.position ?? widget.nextPosition;
    final splitItems = <BillItemModel>[];

    for (var i = 0; i < _splitCount; i++) {
      final sharePaise = sharesMap['p$i']!;
      splitItems.add(
        BillItemModel(
          id: 'temp_split_${DateTime.now().millisecondsSinceEpoch}_$i',
          sessionId: widget.initialItem?.sessionId ?? 'draft_session',
          name: '$name (Part ${i + 1}/$_splitCount)',
          pricePaise: sharePaise,
          position: basePos + i,
        ),
      );
    }

    Navigator.of(context).pop(LineItemEditResult.split(splitItems));
  }

  void _handleDelete() {
    Navigator.of(context).pop(const LineItemEditResult.delete());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + bottomInset,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? Colors.white24
                    : Colors.black12,
                borderRadius: AppRadius.roundedFull,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isEditing ? 'Edit Line Item' : 'Add Line Item',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (_isEditing)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.errorRed),
                  tooltip: 'Delete Item',
                  onPressed: _handleDelete,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Item Name Field
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Item Name',
              hintText: 'e.g. Garlic Naan',
              prefixIcon: Icon(Icons.restaurant_menu_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Price Field
          TextField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            decoration: const InputDecoration(
              labelText: 'Price (₹)',
              hintText: 'e.g. 150.00',
              prefixText: '₹ ',
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.errorRed, fontSize: 13),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),

          // Split Controls (if editing)
          if (_isEditing) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.05)
                    : AppColors.radiantVioletSoft.withValues(alpha: 0.5),
                borderRadius: AppRadius.roundedMd,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.call_split_rounded,
                    color: AppColors.radiantViolet,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Split item into $_splitCount parts',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 2, label: Text('2x')),
                      ButtonSegment(value: 3, label: Text('3x')),
                      ButtonSegment(value: 4, label: Text('4x')),
                    ],
                    selected: {_splitCount},
                    onSelectionChanged: (set) {
                      setState(() => _splitCount = set.first);
                    },
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: _handleSplit,
                    child: const Text('Split'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // Save / Add CTA
          ElevatedButton(
            onPressed: _handleSave,
            child: Text(_isEditing ? 'Save Changes' : 'Add Item'),
          ),
        ],
      ),
    );
  }
}
