import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../core/parse_utils.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../reports/export_service.dart';

class WorksheetDetailScreen extends ConsumerStatefulWidget {
  const WorksheetDetailScreen({super.key, required this.worksheetId});
  final String worksheetId;

  @override
  ConsumerState<WorksheetDetailScreen> createState() => _WorksheetDetailScreenState();
}

class _WorksheetDetailScreenState extends ConsumerState<WorksheetDetailScreen> {
  Map<String, dynamic>? _worksheet;
  bool _loading = true;
  bool _exporting = false;
  String? _error;

  static const _statusLabels = {
    'draft': 'Rozpracovaný',
    'submitted': 'Odevzdaný',
    'reviewed': 'Zkontrolovaný',
    'ready_for_invoice': 'Připravený k fakturaci',
    'invoiced': 'Vyfakturovaný',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(dioProvider).get('/api/worksheets/${widget.worksheetId}');
      if (!mounted) return;
      setState(() {
        _worksheet = res.data as Map<String, dynamic>;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.response?.data?['message'] as String? ?? 'Nepodařilo se načíst soupis';
      });
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) return '—';
    final dt = DateTime.tryParse(value.toString());
    if (dt == null) return value.toString();
    return DateFormat('dd.MM.yyyy').format(dt.toLocal());
  }

  String _formatDateTime(dynamic value) {
    if (value == null) return '—';
    final dt = DateTime.tryParse(value.toString());
    if (dt == null) return value.toString();
    return DateFormat('dd.MM.yyyy HH:mm').format(dt.toLocal());
  }

  Future<void> _exportFile({required String path, required String extension}) async {
    setState(() => _exporting = true);
    try {
      final res = await ref.read(dioProvider).get(
            path,
            options: Options(responseType: ResponseType.bytes),
          );
      final label = extension.toUpperCase();
      final bytes = normalizeExportBytes(res.data, exportLabel: label);
      final job = _worksheet?['job'] as Map<String, dynamic>?;
      final project = job?['projectNumber'] ?? 'soupis';
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final filePath = await saveExportFile(
        bytes: bytes,
        fileName: 'soupis_${project}_$date.$extension',
        extension: extension,
        exportLabel: label,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label uloženo: $filePath')),
      );
    } on ExportSaveCancelled {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uložení zrušeno')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.response?.data?['message'] ?? 'Export selhal')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _changeStatus() async {
    final ws = _worksheet;
    if (ws == null) return;
    final auth = ref.read(authServiceProvider);
    final current = ws['status'] as String? ?? 'draft';
    final allowed = (ws['allowedStatusTargets'] as List?)?.cast<String>() ?? [];

    if (allowed.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pro tuto roli není dostupná změna stavu')),
      );
      return;
    }

    String? selected = allowed.first;
    final commentCtrl = TextEditingController();
    final needsComment = auth.canReviewWorksheet || auth.canInvoiceWorksheet;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Změnit stav soupisu'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Aktuální stav: ${_statusLabels[current] ?? current}'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selected,
                  decoration: const InputDecoration(labelText: 'Nový stav'),
                  items: allowed
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(_statusLabels[s] ?? s),
                          ))
                      .toList(),
                  onChanged: (v) => setDialog(() => selected = v),
                ),
                if (needsComment) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Komentář (volitelné)',
                    ),
                    maxLines: 2,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Zrušit')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Uložit')),
          ],
        ),
      ),
    );

    if (confirmed != true || selected == null) return;

    try {
      await ref.read(dioProvider).patch('/api/worksheets/${widget.worksheetId}/status', data: {
        'status': selected,
        if (commentCtrl.text.trim().isNotEmpty) 'comment': commentCtrl.text.trim(),
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stav změněn na ${_statusLabels[selected] ?? selected}')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.response?.data?['message'] ?? 'Chyba změny stavu')),
      );
    } finally {
      commentCtrl.dispose();
    }
  }

  bool _canChangeStatus(AuthService auth) {
    final allowed = (_worksheet?['allowedStatusTargets'] as List?) ?? [];
    return allowed.isNotEmpty &&
        (auth.canSubmitWorksheet ||
            auth.canReviewWorksheet ||
            auth.canInvoiceWorksheet);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail soupisu'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _buildContent(auth),
    );
  }

  Widget _buildContent(AuthService auth) {
    final ws = _worksheet!;
    final job = ws['job'] as Map<String, dynamic>?;
    final workers = (ws['workers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final items = (ws['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final history = (ws['statusHistory'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final status = ws['status'] as String? ?? 'draft';
    final totalValue = ws['totalValue'];
    final itemCount = ws['itemCount'] ?? items.length;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AppCard(
          showChevron: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${job?['projectNumber'] ?? ''} ${job?['name'] ?? ''}'.trim(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              _infoRow(
                'Stav',
                StatusBadge(
                  status: status,
                  label: _statusLabels[status] ?? status,
                ),
              ),
              _infoRow('Vytvořeno', Text(_formatDateTime(ws['createdAt']))),
              _infoRow(
                'Období',
                Text('${_formatDate(ws['periodFrom'])} – ${_formatDate(ws['periodTo'])}'),
              ),
              _infoRow(
                'Pracovníci',
                Text(workers.map((w) => (w['user'] as Map?)?['displayName'] ?? '').join(', ')),
              ),
              _infoRow('Počet položek', Text('$itemCount')),
              if (totalValue != null)
                _infoRow('Celková hodnota', Text('${parseNum(totalValue).toStringAsFixed(2)} Kč')),
              if ((ws['note'] as String?)?.isNotEmpty == true)
                _infoRow('Poznámka', Text(ws['note'] as String)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            AppPrimaryButton(
              label: 'Stáhnout PDF',
              icon: Icons.picture_as_pdf,
              loading: _exporting,
              fullWidth: false,
              onPressed: _exporting
                  ? null
                  : () => _exportFile(
                        path: '/api/worksheets/${widget.worksheetId}/export/pdf',
                        extension: 'pdf',
                      ),
            ),
            AppSecondaryButton(
              label: 'Stáhnout CSV',
              icon: Icons.table_chart,
              fullWidth: false,
              onPressed: _exporting
                  ? null
                  : () => _exportFile(
                        path: '/api/worksheets/${widget.worksheetId}/export/csv',
                        extension: 'csv',
                      ),
            ),
            if (_canChangeStatus(auth))
              AppSecondaryButton(
                label: 'Změnit stav',
                icon: Icons.sync_alt,
                fullWidth: false,
                onPressed: _changeStatus,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader(title: 'Položky soupisu', style: SectionHeaderStyle.h3),
        if (items.isEmpty)
          const EmptyState(
            message: 'Soupis neobsahuje položky',
            icon: Icons.list_alt_outlined,
          )
        else
          ...items.map((item) {
            final unit = item['unitPrice'];
            final total = item['totalPrice'];
            final unitVal = parseNumOrNull(unit);
            final totalVal = parseNumOrNull(total);
            final priceText = totalVal != null
                ? '${totalVal.toStringAsFixed(2)} Kč'
                : (unitVal != null ? '${unitVal.toStringAsFixed(2)} Kč/ks' : null);
            return AppCard(
              showChevron: false,
              title: '#${item['sealNumber']} · ${item['entryType']} · ${item['dimension']}',
              subtitle: 'Počet: ${item['quantity']}',
              trailing: priceText != null
                  ? Text(
                      priceText,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    )
                  : null,
            );
          }),
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader(title: 'Historie stavu', style: SectionHeaderStyle.h3),
        if (history.isEmpty)
          const EmptyState(
            message: 'Zatím bez záznamů',
            icon: Icons.history,
          )
        else
          ...history.map((entry) {
            final user = entry['user'] as Map<String, dynamic>?;
            final meta = entry['metadata'] as Map<String, dynamic>?;
            final comment = meta?['comment'] as String?;
            return AppCard(
              showChevron: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDateTime(entry['createdAt']),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text('${user?['displayName'] ?? '—'} změnil status:'),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${_statusLabels[entry['oldValue']] ?? entry['oldValue']} → '
                    '${_statusLabels[entry['newValue']] ?? entry['newValue']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (comment != null && comment.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text('Komentář: $comment'),
                    ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _infoRow(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }
}
