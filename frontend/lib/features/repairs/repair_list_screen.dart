import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/design_tokens.dart';
import '../../widgets/app_top_actions.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../reports/export_service.dart';
import '../seals/seal_bulk_actions.dart';

String _formatDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final local = dt.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Seznam oprav — modul Oprava (online-only v1). Worker vidí jen opravy
/// zakázek, jichž je účastníkem (vynuceno na backendu); export jen pro
/// vedení/admin.
class RepairListScreen extends ConsumerStatefulWidget {
  const RepairListScreen({super.key});

  @override
  ConsumerState<RepairListScreen> createState() => _RepairListScreenState();
}

class _RepairListScreenState extends ConsumerState<RepairListScreen> {
  List<Map<String, dynamic>> _repairs = [];
  bool _loading = true;
  String? _error;
  Set<String> _selectedIds = {};

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
      final res = await ref.read(dioProvider).get('/api/repairs');
      final list = (res.data as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _repairs = list;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e, fallback: 'Opravy se nepodařilo načíst');
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Opravy se nepodařilo načíst: $e';
        _loading = false;
      });
    }
  }

  bool get _canExport => ref.read(authServiceProvider).canExportRepairs;

  void _toggleSelect(String id, bool? value) {
    setState(() {
      if (value == true) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  Future<void> _exportSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final ok = await confirmBulkAction(
      context,
      title: 'Export vybraných oprav',
      count: count,
      message: 'Exportovat $count oprav do CSV?',
      confirmLabel: 'Exportovat',
    );
    if (!ok) return;

    try {
      final res = await ref.read(dioProvider).post(
            '/api/repairs/bulk-export/csv',
            data: {'ids': _selectedIds.toList()},
            options: Options(responseType: ResponseType.bytes),
          );
      final bytes = normalizeExportBytes(res.data, exportLabel: 'CSV export');
      await saveExportFile(
        bytes: bytes,
        fileName: 'vybrane-opravy',
        extension: 'csv',
        exportLabel: 'CSV export',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exportováno $count oprav')),
      );
      setState(() => _selectedIds = {});
    } on ExportSaveCancelled {
      return;
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e, fallback: 'Export selhal'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export selhal: $e')),
      );
    }
  }

  Widget _row(Map<String, dynamic> r) {
    final id = r['id'] as String;
    final job = r['job'] as Map<String, dynamic>?;
    final floor = r['floor'] as Map<String, dynamic>?;
    final author = r['createdBy'] as Map<String, dynamic>?;
    final note = (r['note'] as String?) ?? '';
    final preview = note.length > 80 ? '${note.substring(0, 80)}…' : note;
    final canSelect = _canExport;

    return AppCard(
      leading: const AppIconBox(
        icon: Icons.build_outlined,
        backgroundColor: AppColors.bgSecondary,
        color: AppColors.textPrimary,
      ),
      title: 'Ucpávka #${r['sealNumber']} — ${job?['name'] ?? job?['projectNumber'] ?? ''}',
      subtitle:
          '${floor?['name'] ?? ''} · ${author?['displayName'] ?? ''} · ${_formatDate(r['createdAt'] as String?)}'
          '${preview.isNotEmpty ? '\n$preview' : ''}',
      trailing: canSelect
          ? Checkbox(
              value: _selectedIds.contains(id),
              onChanged: (v) => _toggleSelect(id, v),
            )
          : null,
      onTap: () => context.push('/repairs/$id').then((_) => _load()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Opravy'),
        actions: [
          const AppTopActions(),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      bottomNavigationBar: _canExport && _selectedIds.isNotEmpty
          ? Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Text(
                      '${_selectedIds.length} vybráno',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _exportSelected,
                      icon: const Icon(Icons.download),
                      label: const Text('Export CSV'),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: AppSpacing.md),
                        TextButton(
                            onPressed: _load, child: const Text('Zkusit znovu')),
                      ],
                    ),
                  ),
                )
              : _repairs.isEmpty
                  ? const EmptyState(
                      message: 'Zatím nejsou žádné opravy.',
                      icon: Icons.build_outlined,
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: _repairs.length,
                      itemBuilder: (_, i) => _row(_repairs[i]),
                    ),
    );
  }
}
