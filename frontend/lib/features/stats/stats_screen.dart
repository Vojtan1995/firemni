import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../core/parse_utils.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../home/action_items_card.dart';
import '../worksheets/worksheet_navigation.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _jobs = [];
  String? _filterJobId;
  String? _filterStatus;

  @override
  void initState() {
    super.initState();
    _loadJobs();
    _load();
  }

  Future<void> _loadJobs() async {
    final role = ref.read(authUserProvider)?['role'] as String?;
    if (role != 'vedeni' && role != 'admin') return;
    try {
      final res =
          await ref.read(dioProvider).get('/api/reports/filter-options');
      final jobs =
          (res.data['jobs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (mounted) setState(() => _jobs = jobs);
    } catch (_) {}
  }

  Map<String, String> get _queryParams {
    final params = <String, String>{};
    if (_filterJobId != null && _filterJobId!.isNotEmpty) {
      params['jobId'] = _filterJobId!;
    }
    if (_filterStatus != null && _filterStatus!.isNotEmpty) {
      params['status'] = _filterStatus!;
    }
    return params;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(dioProvider).get(
            '/api/stats/overview',
            queryParameters: _queryParams.isEmpty ? null : _queryParams,
          );
      if (!mounted) return;
      setState(() {
        _stats = Map<String, dynamic>.from(res.data as Map);
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.response?.statusCode == 403
            ? 'Nemáte oprávnění k statistikám'
            : 'Nepodařilo se načíst statistiky';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Nepodařilo se načíst statistiky';
        _loading = false;
      });
    }
  }

  void _goSoupisy(
      {String? status, String? jobId, String? reportStatus, String? workerId}) {
    goToSoupisy(
      context,
      status: status,
      jobId: jobId,
      reportStatus: reportStatus,
      workerId: workerId,
    );
  }

  Widget _kpiGrid(List<Widget> cards) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.4,
      children: cards,
    );
  }

  Widget _kpi(
    String label,
    dynamic value, {
    IconData? icon,
    Color? accent,
    VoidCallback? onTap,
  }) {
    return KpiCard(
      label: label,
      value: value?.toString() ?? '0',
      icon: icon,
      accentColor: accent,
      onTap: onTap,
    );
  }

  Widget _buildFilterBar() {
    return AppCard(
      showChevron: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String?>(
            initialValue: _filterJobId,
            decoration: const InputDecoration(labelText: 'Zakázka'),
            items: [
              const DropdownMenuItem(
                  value: null, child: Text('Všechny zakázky')),
              ..._jobs.map(
                (j) => DropdownMenuItem(
                  value: j['id'] as String,
                  child: Text('${j['projectNumber']} ${j['name']}'),
                ),
              ),
            ],
            onChanged: (v) {
              setState(() => _filterJobId = v);
              _load();
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String?>(
            initialValue: _filterStatus,
            decoration: const InputDecoration(labelText: 'Stav ucpávky'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Všechny stavy')),
              DropdownMenuItem(value: 'draft', child: Text('Rozpracované')),
              DropdownMenuItem(value: 'checked', child: Text('Zkontrolované')),
              DropdownMenuItem(value: 'invoiced', child: Text('Fakturované')),
            ],
            onChanged: (v) {
              setState(() => _filterStatus = v);
              _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerStats(Map<String, dynamic> s) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SectionHeader(title: 'Moje statistiky'),
        _kpiGrid([
          _kpi('Dnes', s['sealsToday'], icon: Icons.today),
          _kpi('Tento týden', s['sealsThisWeek'], icon: Icons.date_range),
          _kpi('Tento měsíc', s['sealsThisMonth'], icon: Icons.calendar_month),
          _kpi('Rozpracované', s['draft'], accent: AppColors.info),
          _kpi('Zkontrolované', s['checked'], accent: AppColors.success),
          _kpi(
            'Vrácené k opravě',
            s['returnedForFix'],
            accent: AppColors.error,
          ),
          _kpi(
            'Bez fotky',
            s['missingPhotos'],
            accent: AppColors.warning,
            icon: Icons.photo_camera_outlined,
          ),
          _kpi('Fotek', s['photosAdded'], icon: Icons.photo_camera),
          _kpi('Soupisů', s['worksheetCount'], icon: Icons.description),
          _kpi('Odhad hodnoty (Kč)', s['estimatedValueCzk'],
              accent: AppColors.accent),
        ]),
        if (s['byJob'] is List && (s['byJob'] as List).isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(
              title: 'Práce podle zakázek', style: SectionHeaderStyle.h3),
          ...(s['byJob'] as List).map((j) {
            final m = j as Map<String, dynamic>;
            final count = parseNum(m['count']);
            final jobId = m['jobId'] as String?;
            return AppCard(
              showChevron: jobId != null,
              onTap: jobId != null ? () => context.go('/floors/$jobId') : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${m['projectNumber']} ${m['name']}',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                      Text(
                        '${m['count']}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  if (count > 0) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ClipRRect(
                      borderRadius: AppRadius.smAll,
                      child: LinearProgressIndicator(
                        value: (count / 20).clamp(0, 1),
                        minHeight: 6,
                        backgroundColor: AppColors.bgSecondary,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildManagementStats(Map<String, dynamic> s) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SectionHeader(title: 'Dashboard vedení'),
        if (_jobs.isNotEmpty) ...[
          _buildFilterBar(),
          const SizedBox(height: AppSpacing.lg),
        ],
        _kpiGrid([
          _kpi('Ucpávek celkem', s['totalSeals'], icon: Icons.inventory_2),
          _kpi('Rozpracované', s['draft'], accent: AppColors.info),
          _kpi('Zkontrolované', s['checked'], accent: AppColors.success),
          _kpi('Fakturované', s['invoiced'], accent: AppColors.textMuted),
          _kpi(
            'Vrácené',
            s['returnedSeals'],
            accent: AppColors.error,
            onTap: () => context.push(actionSearchRoute('returned')),
          ),
          _kpi(
            'Bez fotky',
            s['missingPhotos'],
            accent: AppColors.warning,
            icon: Icons.photo_camera_outlined,
            onTap: () => context.push(actionSearchRoute('no_photo')),
          ),
          _kpi(
            'Čeká sync',
            s['syncPending'],
            accent: AppColors.info,
            icon: Icons.sync_problem,
            onTap: () => context.push('/sync'),
          ),
          _kpi(
            'Nezkontrolované',
            s['uncheckedSeals'],
            accent: AppColors.warning,
          ),
          _kpi(
            'Nevyfakturované',
            s['uninvoicedWork'],
            accent: AppColors.warning,
          ),
          _kpi(
            'Připraveno k fakturaci',
            s['readyForInvoice'],
            accent: AppColors.accent,
            onTap: () => _goSoupisy(status: 'ready_for_invoice'),
          ),
          _kpi(
            'Celkem dokončeno/archivováno',
            s['completedArchivedJobs'],
            icon: Icons.archive_outlined,
            accent: AppColors.textMuted,
          ),
        ]),
        if (s['byJobDetailed'] is List &&
            (s['byJobDetailed'] as List).isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(
              title: 'Přehled podle zakázek', style: SectionHeaderStyle.h3),
          ...(s['byJobDetailed'] as List).map((j) {
            final m = j as Map<String, dynamic>;
            final jobId = m['jobId'] as String?;
            return AppCard(
              showChevron: jobId != null,
              onTap: jobId != null ? () => context.go('/floors/$jobId') : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${m['projectNumber']} ${m['name']}',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Celkem ${m['total']} · Rozpr. ${m['draft']} · Zkont. ${m['checked']} · Fakt. ${m['invoiced']}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                  ),
                  if (parseNum(m['missingPhotos']) > 0 ||
                      parseNum(m['returned']) > 0)
                    Text(
                      'Bez fotky: ${m['missingPhotos']} · Vrácené: ${m['returned']}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.warning,
                          ),
                    ),
                ],
              ),
            );
          }),
        ],
        if (s['syncPendingByUser'] is List &&
            (s['syncPendingByUser'] as List).isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(
              title: 'Čekající synchronizace', style: SectionHeaderStyle.h3),
          ...(s['syncPendingByUser'] as List).map((u) {
            final m = u as Map<String, dynamic>;
            return AppCard(
              showChevron: true,
              onTap: () => context.push('/sync'),
              title: m['displayName'] as String? ?? '',
              trailing: Text('${m['count']}'),
            );
          }),
        ],
        if (s['jobsWithoutActivity'] is List &&
            (s['jobsWithoutActivity'] as List).isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(
              title: 'Zakázky bez aktivity', style: SectionHeaderStyle.h3),
          ...(s['jobsWithoutActivity'] as List).map((j) {
            final m = j as Map<String, dynamic>;
            return AppCard(
              showChevron: true,
              borderColor: AppColors.warning.withValues(alpha: 0.4),
              leading:
                  const Icon(Icons.warning_amber, color: AppColors.warning),
              title: '${m['projectNumber']} ${m['name']}',
              onTap: () => context.go(jobsWithoutActivityRoute),
            );
          }),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authUserProvider)?['role'] as String?;
    final title = role == 'worker' ? 'Moje statistiky' : 'Dashboard';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(message: _error!, icon: Icons.error_outline)
              : _stats == null
                  ? const EmptyState(message: 'Žádná data')
                  : Builder(
                      builder: (context) {
                        final s = _stats!;
                        final r = s['role'] as String? ?? role;
                        if (r == 'worker') return _buildWorkerStats(s);
                        return _buildManagementStats(s);
                      },
                    ),
    );
  }
}
