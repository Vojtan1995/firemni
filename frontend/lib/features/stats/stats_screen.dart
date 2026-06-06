import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../core/parse_utils.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;

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
      final res = await ref.read(dioProvider).get('/api/stats/overview');
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

  void _goSoupisy({String? status, String? jobId, String? reportStatus, String? workerId}) {
    final params = <String, String>{};
    if (status != null) params['status'] = status;
    if (jobId != null) params['jobId'] = jobId;
    if (reportStatus != null) params['reportStatus'] = reportStatus;
    if (workerId != null) params['workerId'] = workerId;
    final uri = Uri(path: '/soupisy', queryParameters: params.isEmpty ? null : params);
    context.go(uri.toString());
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
          _kpi('Fotek', s['photosAdded'], icon: Icons.photo_camera),
          _kpi('Soupisů', s['worksheetCount'], icon: Icons.description),
          _kpi('Odhad hodnoty (Kč)', s['estimatedValueCzk'], accent: AppColors.accent),
        ]),
        if (s['byJob'] is List && (s['byJob'] as List).isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Práce podle zakázek', style: SectionHeaderStyle.h3),
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
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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

  Widget _buildUcetniStats(Map<String, dynamic> s) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SectionHeader(title: 'Statistiky fakturace'),
        _kpiGrid([
          _kpi(
            'Soupisů celkem',
            s['worksheetCount'],
            icon: Icons.description,
            onTap: () => _goSoupisy(),
          ),
          _kpi(
            'Připraveno k fakturaci',
            s['readyForInvoice'],
            accent: AppColors.warning,
            onTap: () => _goSoupisy(status: 'ready_for_invoice'),
          ),
          _kpi(
            'Vyfakturované',
            s['invoiced'],
            accent: AppColors.textMuted,
            onTap: () => _goSoupisy(status: 'invoiced'),
          ),
          _kpi(
            'Čeká na fakturaci',
            s['pendingInvoice'],
            accent: AppColors.info,
            onTap: () => _goSoupisy(status: 'reviewed'),
          ),
        ]),
        if (s['byJob'] is List && (s['byJob'] as List).isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Soupisy podle zakázek', style: SectionHeaderStyle.h3),
          ...(s['byJob'] as List).map((j) {
            final m = j as Map<String, dynamic>;
            final jobId = m['jobId'] as String?;
            return AppCard(
              showChevron: jobId != null,
              onTap: jobId != null ? () => _goSoupisy(jobId: jobId) : null,
              title: '${m['projectNumber']} ${m['name']}',
              trailing: Text('${m['count']}'),
            );
          }),
        ],
        if (s['byWorker'] is List && (s['byWorker'] as List).isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Soupisy podle pracovníků', style: SectionHeaderStyle.h3),
          ...(s['byWorker'] as List).map((w) {
            final m = w as Map<String, dynamic>;
            final userId = m['userId'] as String?;
            return AppCard(
              showChevron: userId != null,
              onTap: userId != null ? () => _goSoupisy(workerId: userId) : null,
              title: m['displayName'] as String? ?? '',
              trailing: Text('${m['count']}'),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildManagementStats(Map<String, dynamic> s) {
    final workers = s['byWorker'] is List ? s['byWorker'] as List : <dynamic>[];
    final maxWorkerCount = workers.isEmpty
        ? 1.0
        : workers
            .map((w) => parseNum((w as Map)['count']))
            .fold<double>(0, (a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SectionHeader(title: 'Dashboard'),
        _kpiGrid([
          _kpi(
            'Ucpávek celkem',
            s['totalSeals'],
            icon: Icons.inventory_2,
            onTap: () => _goSoupisy(),
          ),
          _kpi(
            'Rozpracované',
            s['draft'],
            accent: AppColors.info,
            onTap: () => _goSoupisy(reportStatus: 'draft'),
          ),
          _kpi(
            'Zkontrolované',
            s['checked'],
            accent: AppColors.success,
            onTap: () => _goSoupisy(reportStatus: 'checked'),
          ),
          _kpi(
            'Fakturované',
            s['invoiced'],
            accent: AppColors.textMuted,
            onTap: () => _goSoupisy(reportStatus: 'invoiced'),
          ),
          _kpi(
            'Nezkontrolované',
            s['uncheckedSeals'],
            accent: AppColors.warning,
            onTap: () => _goSoupisy(reportStatus: 'draft'),
          ),
          _kpi(
            'Nevyfakturované',
            s['uninvoicedWork'],
            accent: AppColors.warning,
            onTap: () => _goSoupisy(reportStatus: 'checked'),
          ),
          _kpi(
            'Připraveno k fakturaci',
            s['readyForInvoice'],
            accent: AppColors.accent,
            onTap: () => _goSoupisy(status: 'ready_for_invoice'),
          ),
        ]),
        if (workers.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Výkon pracovníků', style: SectionHeaderStyle.h3),
          ...workers.map((w) {
            final m = w as Map<String, dynamic>;
            final count = parseNum(m['count']);
            final workerId = (m['userId'] ?? m['workerId']) as String?;
            return AppCard(
              showChevron: workerId != null,
              onTap: workerId != null
                  ? () => _goSoupisy(workerId: workerId)
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          m['displayName'] as String? ?? '',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: AppRadius.smAll,
                    child: LinearProgressIndicator(
                      value: maxWorkerCount > 0 ? count / maxWorkerCount : 0,
                      minHeight: 6,
                      backgroundColor: AppColors.bgSecondary,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
        if (s['jobsWithoutActivity'] is List &&
            (s['jobsWithoutActivity'] as List).isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Zakázky bez aktivity', style: SectionHeaderStyle.h3),
          ...(s['jobsWithoutActivity'] as List).map((j) {
            final m = j as Map<String, dynamic>;
            return AppCard(
              showChevron: true,
              borderColor: AppColors.warning.withValues(alpha: 0.4),
              leading: const Icon(Icons.warning_amber, color: AppColors.warning),
              title: '${m['projectNumber']} ${m['name']}',
              onTap: () => context.go('/jobs-admin'),
            );
          }),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authUserProvider)?['role'] as String?;
    final title = role == 'worker'
        ? 'Moje statistiky'
        : role == 'ucetni'
            ? 'Statistiky fakturace'
            : 'Dashboard';

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
                        if (r == 'ucetni') return _buildUcetniStats(s);
                        return _buildManagementStats(s);
                      },
                    ),
    );
  }
}
