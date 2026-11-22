import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:spliqo/core/constants/app_tokens.dart';
import 'package:spliqo/core/router/route_paths.dart';
import 'package:spliqo/core/theme/app_colors.dart';
import 'package:spliqo/core/theme/app_gradients.dart';
import 'package:spliqo/core/utils/currency_formatter.dart';
import 'package:spliqo/core/utils/receipt_image_service.dart';
import 'package:spliqo/domain/models/session.dart';
import 'package:spliqo/presentation/screens/active_room_screen.dart';
import 'package:spliqo/presentation/widgets/invite_share_sheet.dart';
import 'package:spliqo/presentation/widgets/line_item_edit_sheet.dart';
import 'package:spliqo/presentation/widgets/receipt_preview_dialog.dart';
import 'package:spliqo/state/auth_provider.dart';
import 'package:spliqo/state/session_providers.dart';

/// Screen 1: Host Receipt Ingestion & Draft Review (Section 3.1 & 10.5 of Standards)
/// Displays extracted line items, reconciles adjustments, and allows activation.
class ReceiptReviewScreen extends ConsumerStatefulWidget {
  const new({
    this.initialSession,
    this.imageService = const ReceiptImageService(),
    super.key,
  });

  final SessionModel? initialSession;
  final ReceiptImageService imageService;

  @override
  ConsumerState<ReceiptReviewScreen> createState() =>
      _ReceiptReviewScreenState();
}

class _ReceiptReviewScreenState extends ConsumerState<ReceiptReviewScreen> {
  SessionModel? _session;
  ReceiptImageFile? _imageFile;

  List<BillItemModel> _items = [];
  int _taxPaise = 0;
  int _serviceChargePaise = 0;
  int _discountPaise = 0;
  int _roundOffPaise = 0;
  int _totalPaise = 0;
  String _sessionTitle = 'Restaurant Bill';

  bool _isLoading = false;
  String _loadingMessage = 'Loading...';
  String? _errorMessage;

  // Live reconciliation engine properties
  int get _calculatedSubtotalPaise =>
      _items.fold<int>(0, (sum, item) => sum + item.pricePaise);

  int get _expectedTotalPaise =>
      _calculatedSubtotalPaise +
      _taxPaise +
      _serviceChargePaise -
      _discountPaise +
      _roundOffPaise;

  bool get _isReconciled =>
      _expectedTotalPaise == _totalPaise && _items.isNotEmpty;

  int get _reconciliationDiffPaise => _totalPaise - _expectedTotalPaise;

  @override
  void initState() {
    super.initState();
    if (widget.initialSession != null) {
      _loadSessionState(widget.initialSession!);
    }
  }

  void _loadSessionState(SessionModel session) {
    setState(() {
      _session = session;
      _sessionTitle = session.title;
      _items = List<BillItemModel>.from(session.items);
      _taxPaise = session.taxPaise;
      _serviceChargePaise = session.serviceChargePaise;
      _discountPaise = session.discountPaise;
      _roundOffPaise = session.roundOffPaise;
      _totalPaise = session.totalPaise;
    });
  }

  Future<void> _handlePickImage(ImageSource source) async {
    setState(() {
      _errorMessage = null;
    });

    try {
      final imageFile =
          await widget.imageService.pickAndValidateReceipt(source: source);
      if (imageFile == null) return;

      setState(() {
        _imageFile = imageFile;
        _isLoading = true;
        _loadingMessage = 'Gemini Vision is parsing receipt items & taxes...';
      });

      final hostDisplayName =
          ref.read(authNotifierProvider).user?.displayName.trim();
      final effectiveHostName =
          (hostDisplayName != null && hostDisplayName.isNotEmpty)
              ? hostDisplayName
              : 'Host';

      final repo = ref.read(sessionRepositoryProvider);
      final parseResp = await repo.parseReceipt(
        imageBytes: imageFile.bytes,
        filename: imageFile.filename,
        hostDisplayName: effectiveHostName,
      );

      final sessionData = parseResp['session'] as Map<String, dynamic>;
      final parsedSession = SessionModel.fromJson(sessionData);

      _loadSessionState(parsedSession);
      setState(() {
        _isLoading = false;
      });
    } on Object catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Receipt scan error: $e\nYou can retry or enter items manually below.';
      });
    }
  }

  void _enterManualItemsFallback() {
    const defaultItem = BillItemModel(
      id: 'manual_1',
      sessionId: 'draft_manual',
      name: 'Main Dish',
      pricePaise: 50000, // ₹500.00
      position: 0,
    );

    setState(() {
      _sessionTitle = 'Dinner Table';
      _items = [defaultItem];
      _taxPaise = 2500; // 5% GST (₹25.00)
      _serviceChargePaise = 0;
      _discountPaise = 0;
      _roundOffPaise = 0;
      _totalPaise = 52500; // ₹525.00
      _errorMessage = null;
      _session = SessionModel(
        id: 'draft_manual_${DateTime.now().millisecondsSinceEpoch}',
        hostId: ref.read(authNotifierProvider).user?.id ?? 'host',
        title: _sessionTitle,
        currency: 'INR',
        subtotalPaise: 50000,
        taxPaise: 2500,
        serviceChargePaise: 0,
        discountPaise: 0,
        roundOffPaise: 0,
        totalPaise: 52500,
        status: SessionStatus.draft,
        revision: 0,
        items: const [defaultItem],
      );
    });
  }

  void _autoBalanceRoundOff() {
    setState(() {
      _roundOffPaise += _reconciliationDiffPaise;
    });
    unawaited(HapticFeedback.lightImpact());
  }

  Future<void> _editLineItem(BillItemModel? item, {int nextPos = 0}) async {
    final result = await LineItemEditSheet.show(
      context,
      initialItem: item,
      nextPosition: nextPos,
    );
    if (result == null) return;

    setState(() {
      switch (result.action) {
        case LineItemEditAction.save:
          if (item == null) {
            _items.add(result.item!);
          } else {
            final idx = _items.indexWhere((i) => i.id == item.id);
            if (idx != -1) {
              _items[idx] = result.item!;
            }
          }
        case LineItemEditAction.split:
          if (item != null) {
            final idx = _items.indexWhere((i) => i.id == item.id);
            if (idx != -1) {
              _items
                ..removeAt(idx)
                ..insertAll(idx, result.splitItems!);
            }
          }
        case LineItemEditAction.delete:
          if (item != null) {
            _items.removeWhere((i) => i.id == item.id);
          }
      }
    });
  }

  Future<void> _editAdjustmentValue({
    required String title,
    required int currentValuePaise,
    required ValueChanged<int> onSaved,
  }) async {
    final controller = TextEditingController(
      text: (currentValuePaise / 100).toStringAsFixed(2),
    );

    final updatedPaise = await showDialog<int>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Amount (₹)',
            prefixText: '₹ ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final raw = controller.text.trim().replaceAll(',', '');
              final parts = raw.split('.');
              final rupees = int.tryParse(parts[0]) ?? 0;
              var paise = 0;
              if (parts.length == 2) {
                final p = parts[1].padRight(2, '0');
                paise = int.tryParse(p.length > 2 ? p.substring(0, 2) : p) ?? 0;
              }
              final total = (rupees * 100) + paise;
              Navigator.of(dialogCtx).pop(total);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (updatedPaise != null) {
      setState(() => onSaved(updatedPaise));
    }
  }

  Future<void> _activateSession() async {
    if (!_isReconciled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please balance the receipt before activating. Sum of items and adjustments must equal Total.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Activating session and creating invite link...';
      _errorMessage = null;
    });

    try {
      final repo = ref.read(sessionRepositoryProvider);

      String sessionId;
      if (_session == null || _session!.id.startsWith('draft_manual_')) {
        // Create draft session on backend
        final draftPayload = {
          'title': _sessionTitle,
          'subtotal_paise': _calculatedSubtotalPaise,
          'tax_paise': _taxPaise,
          'service_charge_paise': _serviceChargePaise,
          'discount_paise': _discountPaise,
          'round_off_paise': _roundOffPaise,
          'total_paise': _totalPaise,
          'host_display_name':
              ref.read(authNotifierProvider).user?.displayName ?? 'Host',
          'items': _items
              .asMap()
              .entries
              .map(
                (e) => {
                  'name': e.value.name,
                  'price_paise': e.value.pricePaise,
                  'position': e.key,
                },
              )
              .toList(),
        };
        final created = await repo.createDraftSession(draftPayload);
        sessionId = created.id;
      } else {
        sessionId = _session!.id;
        // Update draft session with any corrections
        final updatePayload = {
          'title': _sessionTitle,
          'subtotal_paise': _calculatedSubtotalPaise,
          'tax_paise': _taxPaise,
          'service_charge_paise': _serviceChargePaise,
          'discount_paise': _discountPaise,
          'round_off_paise': _roundOffPaise,
          'total_paise': _totalPaise,
          'items': _items
              .asMap()
              .entries
              .map(
                (e) => {
                  'name': e.value.name,
                  'price_paise': e.value.pricePaise,
                  'position': e.key,
                },
              )
              .toList(),
        };
        await repo.updateDraftSession(sessionId, updatePayload);
      }

      // Activate session
      final activeSession = await repo.activateSession(sessionId);

      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        if (GoRouter.maybeOf(context) != null) {
          unawaited(context.push(AppRoutes.room(activeSession.id)));
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => ActiveRoomScreen(sessionId: activeSession.id),
            ),
          );
        }
      }
    } on Object catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to activate session: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt Draft Review'),
        centerTitle: true,
        actions: [
          if (_session != null)
            IconButton(
              icon: const Icon(Icons.qr_code_rounded),
              tooltip: 'Table QR & Invite Code',
              onPressed: () {
                unawaited(
                  InviteShareSheet.show(
                    context,
                    sessionId: _session!.id,
                    roomCode: _session!.id.length >= 6
                        ? _session!.id.substring(0, 6).toUpperCase()
                        : _session!.id.toUpperCase(),
                    sessionTitle: _sessionTitle,
                  ),
                );
              },
            ),
          if (_imageFile != null)
            IconButton(
              icon: const Icon(Icons.zoom_in_rounded),
              tooltip: 'Inspect Receipt Image',
              onPressed: () => ReceiptPreviewDialog.show(
                context,
                imageBytes: _imageFile!.bytes,
                title: 'Receipt: $_sessionTitle',
              ),
            ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _loadingMessage,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          : (_session == null && _items.isEmpty)
              ? _buildEmptyState(theme, isDark)
              : _buildReviewContent(theme, isDark),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                gradient: AppGradients.primaryRadiance,
                borderRadius: AppRadius.roundedXl,
                boxShadow: AppShadows.softCard,
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Capture or Upload Receipt',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Take a photo of the restaurant bill. Gemini Vision will automatically extract line items and taxes in integer paise.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.textMutedDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Camera Capture Button
            ElevatedButton.icon(
              onPressed: () => _handlePickImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Take Receipt Photo'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Gallery Upload Button
            OutlinedButton.icon(
              onPressed: () => _handlePickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_rounded),
              label: const Text('Choose from Gallery'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Friendly Manual Fallback Button
            TextButton.icon(
              onPressed: _enterManualItemsFallback,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Enter Line Items Manually'),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.errorRedSoft,
                  borderRadius: AppRadius.roundedSm,
                  border: Border.all(
                    color: AppColors.errorRed.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.errorRed,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReviewContent(ThemeData theme, bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // Header Card with Title and Image Zoom CTA
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _sessionTitle,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: AppRadius.roundedFull,
                      ),
                      child: const Text(
                        'DRAFT',
                        style: TextStyle(
                          color: Color(0xFFB45309),
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Review extracted items, correct misreads, and verify total before room activation.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.textMutedDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
                if (_imageFile != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () => ReceiptPreviewDialog.show(
                      context,
                      imageBytes: _imageFile!.bytes,
                      title: 'Receipt: $_sessionTitle',
                    ),
                    icon: const Icon(Icons.zoom_in_rounded, size: 18),
                    label: const Text('Inspect Physical Receipt'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Line Items Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Line Items (${_items.length})',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            TextButton.icon(
              onPressed: () => _editLineItem(null, nextPos: _items.length),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Item'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),

        // Line Items List
        if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(
              child: Text(
                'No line items. Tap "+ Add Item" to create one.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ..._items.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.radiantVioletSoft,
                  child: Text(
                    '${idx + 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.radiantViolet,
                    ),
                  ),
                ),
                title: Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      CurrencyFormatter.formatPaise(item.pricePaise),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: Colors.grey,
                    ),
                  ],
                ),
                onTap: () => _editLineItem(item),
              ),
            );
          }),

        const SizedBox(height: AppSpacing.md),

        // Adjustments & Summary Card
        Card(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSummaryRow(
                  'Subtotal (Sum of Items)',
                  _calculatedSubtotalPaise,
                ),
                _buildEditableSummaryRow(
                  'Tax / GST',
                  _taxPaise,
                  onEdit: () => _editAdjustmentValue(
                    title: 'Adjust Tax / GST',
                    currentValuePaise: _taxPaise,
                    onSaved: (val) => _taxPaise = val,
                  ),
                ),
                _buildEditableSummaryRow(
                  'Service Charge',
                  _serviceChargePaise,
                  onEdit: () => _editAdjustmentValue(
                    title: 'Adjust Service Charge',
                    currentValuePaise: _serviceChargePaise,
                    onSaved: (val) => _serviceChargePaise = val,
                  ),
                ),
                _buildEditableSummaryRow(
                  'Discount',
                  -_discountPaise,
                  onEdit: () => _editAdjustmentValue(
                    title: 'Adjust Discount',
                    currentValuePaise: _discountPaise,
                    onSaved: (val) => _discountPaise = val,
                  ),
                ),
                _buildEditableSummaryRow(
                  'Round Off',
                  _roundOffPaise,
                  onEdit: () => _editAdjustmentValue(
                    title: 'Adjust Round Off',
                    currentValuePaise: _roundOffPaise,
                    onSaved: (val) => _roundOffPaise = val,
                  ),
                ),
                const Divider(),
                _buildEditableSummaryRow(
                  'Total Bill',
                  _totalPaise,
                  isBold: true,
                  onEdit: () => _editAdjustmentValue(
                    title: 'Set Total Bill',
                    currentValuePaise: _totalPaise,
                    onSaved: (val) => _totalPaise = val,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.sm),

        // Live Subtotal Reconciliation Banner
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: _isReconciled
                ? AppColors.mintFreshSoft
                : AppColors.errorRedSoft,
            borderRadius: AppRadius.roundedMd,
            border: Border.all(
              color: _isReconciled
                  ? AppColors.mintFresh.withValues(alpha: 0.4)
                  : AppColors.errorRed.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    _isReconciled
                        ? Icons.check_circle_rounded
                        : Icons.warning_amber_rounded,
                    color: _isReconciled
                        ? AppColors.mintFresh
                        : AppColors.errorRed,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _isReconciled
                          ? 'Receipt balanced: All line items and adjustments match total exactly.'
                          : 'Reconciliation difference: ${CurrencyFormatter.formatPaise(_reconciliationDiffPaise.abs())} '
                              '(${_reconciliationDiffPaise > 0 ? "Under" : "Over"} total)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _isReconciled
                            ? AppColors.mintFresh
                            : AppColors.errorRed,
                      ),
                    ),
                  ),
                ],
              ),
              if (!_isReconciled) ...[
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _autoBalanceRoundOff,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                  label: const Text('Auto-Balance Round Off'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.errorRed,
                    side: const BorderSide(color: AppColors.errorRed),
                  ),
                ),
              ],
            ],
          ),
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _errorMessage!,
            style: const TextStyle(color: AppColors.errorRed, fontSize: 13),
          ),
        ],

        const SizedBox(height: AppSpacing.lg),

        // Activation Button
        ElevatedButton(
          onPressed: (_isLoading || !_isReconciled) ? null : _activateSession,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          ),
          child: const Text(
            'Activate Session & Invite Participants',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),

        // Extra space for bottom padding
        const SizedBox(height: 80),
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
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
              fontSize: isBold ? 16 : 14,
            ),
          ),
          Text(
            CurrencyFormatter.formatPaise(amountPaise),
            style: TextStyle(
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
              fontSize: isBold ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableSummaryRow(
    String label,
    int amountPaise, {
    required VoidCallback onEdit,
    bool isBold = false,
  }) {
    return InkWell(
      onTap: onEdit,
      borderRadius: AppRadius.roundedSm,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
                    fontSize: isBold ? 16 : 14,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: AppColors.radiantViolet,
                ),
              ],
            ),
            Text(
              CurrencyFormatter.formatPaise(amountPaise),
              style: TextStyle(
                fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
                fontSize: isBold ? 16 : 14,
                color: isBold ? null : AppColors.radiantViolet,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
