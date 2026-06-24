import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/design_tokens.dart';
import '../../core/parse_utils.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../seals/seal_constants.dart';

class WorksheetDetailScreen extends ConsumerStatefulWidget {
  const WorksheetDetailScreen({super.key, required this.worksheetId});
  final String worksheetId;

  @override
  ConsumerState<WorksheetDetailScreen> createState() =>
      _WorksheetDetailScreenState();
}

class _WorksheetDetailScreenState extends ConsumerState<WorksheetDetailScreen> {
  Map<String, dynamic>? _worksheet;
  bool _loading = true;
  String? _error;

  static const _statusLabels = {
    'draft': 'Rozpracovaný',
    'submitted': 'Odevzdaný',
    'reviewed': 'Zkontrolovaný',
    'ready_for_invoice': 'Připravený k fakturaci',
    'invoiced': 'Vyfakturovaný',
    'archived': 'Archivovaný',
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
      final res = await ref
          .read(dioProvider)
          .get('/api/worksheets/${widget.worksheetId}');
      if (!mounted) return;
      setState(() {
        _worksheet = res.data as Map<String, dynamic>;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(e, fallback: 'Nepodařilo se načíst soupis');
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

  Future<void> _deleteWorksheet() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Smazat soupis?'),
        content: const Text(
          'Rozpracovaný soupis bude odstraněn. Tuto akci nelze v aplikaci běžně vrátit zpět.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Zrušit')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Smazat'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(dioProvider)
          .delete('/api/worksheets/${widget.worksheetId}');
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Soupis byl smazán')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                apiErrorMessage(e, fallback: 'Nepodařilo se smazat soupis'))),
      );
    }
  }

  Future<void> _setStatus(String status, {bool requireComment = false}) async {
    String? comment;
    if (requireComment) {
      final ctrl = TextEditingController();
      comment = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Důvod vrácení'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Komentář (povinný)'),
            maxLines: 3,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Zrušit')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Potvrdit'),
            ),
          ],
        ),
      );
      if (comment == null || comment.isEmpty) return;
    }
    try {
      await ref
          .read(dioProvider)
          .patch('/api/worksheets/${widget.worksheetId}/status', data: {
        'status': status,
        if (comment != null) 'comment': comment,
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Stav změněn na ${_statusLabels[status] ?? status}')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(apiErrorMessage(e, fallback: 'Chyba změny stavu'))),
      );
    }
  }

  List<Widget> _workflowButtons(AuthService auth, String status) {
    if (auth.isWorker) {
      if (status == 'draft') {
        return [
          AppPrimaryButton(
            label: 'Odevzdat',
            icon: Icons.send,
            fullWidth: false,
            onPressed: () => _setStatus('submitted'),
          ),
        ];
      }
      if (status == 'submitted') {
        return [
          const Text('Soupis je odevzdaný a uzamčený pro úpravy.'),
        ];
      }
      return [];
    }
    if (auth.canReviewWorksheet && status == 'submitted') {
      return [
        AppPrimaryButton(
          label: 'Schválit',
          fullWidth: false,
          onPressed: () => _setStatus('reviewed'),
        ),
        AppSecondaryButton(
          label: 'Vrátit k opravě',
          fullWidth: false,
          onPressed: () => _setStatus('draft', requireComment: true),
        ),
      ];
    }
    if (_canChangeStatus(auth)) {
      return [
        AppSecondaryButton(
          label: 'Změnit stav',
          icon: Icons.sync_alt,
          fullWidth: false,
          onPressed: _changeStatus,
        ),
      ];
    }
    return [];
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
        const SnackBar(
            content: Text('Pro tuto roli není dostupná změna stavu')),
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
                  key: ValueKey(selected),
                  initialValue: selected,
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
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Zrušit')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Uložit')),
          ],
        ),
      ),
    );

    if (confirmed != true || selected == null) return;

    try {
      await ref
          .read(dioProvider)
          .patch('/api/worksheets/${widget.worksheetId}/status', data: {
        'status': selected,
        if (commentCtrl.text.trim().isNotEmpty)
          'comment': commentCtrl.text.trim(),
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Stav změněn na ${_statusLabels[selected] ?? selected}')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(apiErrorMessage(e, fallback: 'Chyba změny stavu'))),
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

  Future<void> _addItemsToDraft() async {
    final ws = _worksheet;
    final job = ws?['job'] as Map<String, dynamic>?;
    final jobId = job?['id'] as String?;
    if (jobId == null || jobId.isEmpty) return;

    List<Map<String, dynamic>> floors = [];
    try {
      final res = await ref.read(dioProvider).get('/api/jobs/$jobId/floors');
      floors = (res.data as List).cast<Map<String, dynamic>>();
    } catch (_) {}

    if (!mounted) return;

    String? floorId;
    String? status;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Přidat položky'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: floorId,
                  decoration: const InputDecoration(labelText: 'Patro'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Všechna patra'),
                    ),
                    ...floors.map(
                      (f) => DropdownMenuItem(
                        value: f['id'] as String,
                        child: Text(f['name'] as String? ?? ''),
                      ),
                    ),
                  ],
                  onChanged: (v) => setDialog(() => floorId = v),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String?>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Stav ucpávky'),
                  items: const [
                    DropdownMenuItem(
                      value: null,
                      child: Text('Rozpracované a zkontrolované'),
                    ),
                    DropdownMenuItem(
                        value: 'draft', child: Text('Rozpracované')),
                    DropdownMenuItem(
                        value: 'checked', child: Text('Zkontrolované')),
                  ],
                  onChanged: (v) => setDialog(() => status = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Zrušit'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Přidat'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    try {
      final res = await ref.read(dioProvider).post(
        '/api/worksheets/${widget.worksheetId}/populate',
        data: {
          if (floorId != null) 'floorIds': [floorId],
          if (status != null) 'status': status,
        },
      );
      await _load();
      if (!mounted) return;
      final added = (res.data as Map?)?['addedCount'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Přidáno položek: $added')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(apiErrorMessage(e, fallback: 'Přidání položek selhalo'))),
      );
    }
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
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: AppSpacing.md),
                      AppSecondaryButton(
                        label: 'Zkusit znovu',
                        fullWidth: false,
                        onPressed: _load,
                      ),
                    ],
                  ),
                )
              : _buildContent(auth),
    );
  }

  Widget _buildContent(AuthService auth) {
    final ws = _worksheet!;
    final job = ws['job'] as Map<String, dynamic>?;
    final workers =
        (ws['workers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final items = (ws['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final history =
        (ws['statusHistory'] as List?)?.cast<Map<String, dynamic>>() ?? [];
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
                Text(
                    '${_formatDate(ws['periodFrom'])} – ${_formatDate(ws['periodTo'])}'),
              ),
              _infoRow(
                'Pracovníci',
                Text(workers
                    .map((w) => (w['user'] as Map?)?['displayName'] ?? '')
                    .join(', ')),
              ),
              _infoRow('Počet položek', Text('$itemCount')),
              if (totalValue != null)
                _infoRow('Celková hodnota',
                    Text('${parseNum(totalValue).toStringAsFixed(2)} Kč')),
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
            ..._workflowButtons(auth, status),
            if (status == 'draft' && auth.canCreateWorksheet)
              AppSecondaryButton(
                label: 'Přidat položky',
                icon: Icons.playlist_add,
                fullWidth: false,
                onPressed: _addItemsToDraft,
              ),
            if (status == 'draft' && auth.canDeleteWorksheet)
              AppSecondaryButton(
                label: 'Smazat',
                icon: Icons.delete_outline,
                fullWidth: false,
                onPressed: _deleteWorksheet,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader(
            title: 'Položky soupisu', style: SectionHeaderStyle.h3),
        if (items.isEmpty)
          const EmptyState(
            message: 'Soupis neobsahuje položky',
            icon: Icons.list_alt_outlined,
          )
        else
          ...items.map(_buildItemCard),
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader(
            title: 'Historie stavu', style: SectionHeaderStyle.h3),
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

  /// Řemeslo/řemesla: podporuje nové pole `trades` (multi) i staré `trade`.
  String _tradesLabel(Map<String, dynamic> item) {
    final trades = item['trades'];
    if (trades is List && trades.isNotEmpty) {
      return trades.map((t) => sealTradeLabel(t?.toString())).join(', ');
    }
    final single = item['trade'];
    return single == null ? '—' : sealTradeLabel(single.toString());
  }

  String _orDash(dynamic value) {
    if (value == null) return '—';
    final s = value.toString().trim();
    return s.isEmpty ? '—' : s;
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final unitVal = parseNumOrNull(item['unitPrice']);
    final totalVal = parseNumOrNull(item['totalPrice']);
    final qty = parseNumOrNull(item['quantity']) ?? 0;
    final computedTotal = totalVal ?? (unitVal != null ? unitVal * qty : null);
    final unitLabel = item['unit'] as String? ?? 'kus';
    final floorName = (item['floor'] as Map?)?['name'];
    final note = (item['note'] as String?)?.trim();

    return AppCard(
      showChevron: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ucpávka #${_orDash(item['sealNumber'])}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          _itemLine('Patro', _orDash(floorName)),
          _itemLine('Řemeslo', _tradesLabel(item)),
          _itemLine('Systém', _orDash(item['system'])),
          _itemLine('Typ', _orDash(item['entryType'])),
          _itemLine(
              'Materiál / katalogová položka', _orDash(item['catalogId'])),
          _itemLine('Izolace', _orDash(item['insulation'])),
          _itemLine('Umístění', _orDash(item['location'])),
          _itemLine('Rozměr', _orDash(item['dimension'])),
          _itemLine('Množství', '${_orDash(item['quantity'])} $unitLabel'),
          _itemLine(
            'Jedn. cena',
            unitVal != null
                ? '${unitVal.toStringAsFixed(2)} Kč/$unitLabel'
                : '—',
          ),
          _itemLine(
            'Cena celkem',
            computedTotal != null
                ? '${computedTotal.toStringAsFixed(2)} Kč'
                : '—',
            bold: true,
          ),
          if (note != null && note.isNotEmpty) _itemLine('Poznámka', note),
        ],
      ),
    );
  }

  Widget _itemLine(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: bold
                  ? const TextStyle(fontWeight: FontWeight.w600)
                  : Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
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
