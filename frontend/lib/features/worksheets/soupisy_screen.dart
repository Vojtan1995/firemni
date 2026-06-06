import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../reports/reports_screen.dart';

/// Sloučená obrazovka: export soupisu nahoře, uložené soupisy dole.
class SoupisyScreen extends ConsumerStatefulWidget {
  const SoupisyScreen({super.key});

  @override
  ConsumerState<SoupisyScreen> createState() => _SoupisyScreenState();
}

class _SoupisyScreenState extends ConsumerState<SoupisyScreen> {
  final _reportsKey = GlobalKey<ReportsScreenState>();
  List<Map<String, dynamic>> _worksheets = [];
  List<Map<String, dynamic>> _jobs = [];
  bool _loadingWorksheets = true;
  String? _statusFilter;
  String? _jobIdFilter;
  String? _reportStatusFilter;
  String? _reportWorkerId;
  bool _queryParamsApplied = false;

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
    _loadWorksheets();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_queryParamsApplied) return;
    _queryParamsApplied = true;
    final qp = GoRouterState.of(context).uri.queryParameters;
    final status = qp['status'];
    final jobId = qp['jobId'];
    final reportStatus = qp['reportStatus'];
    final workerId = qp['workerId'];
    if (status != null || jobId != null || reportStatus != null || workerId != null) {
      _statusFilter = status;
      _jobIdFilter = jobId;
      _reportStatusFilter = reportStatus;
      _reportWorkerId = workerId;
      _loadWorksheets();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reportsKey.currentState?.applyInitialFilters(
          jobId: jobId,
          status: reportStatus,
          workerId: workerId,
        );
      });
    }
  }

  Future<void> _loadWorksheets() async {
    setState(() => _loadingWorksheets = true);
    final dio = ref.read(dioProvider);
    try {
      final filterRes = await dio.get('/api/reports/filter-options');
      if (!mounted) return;
      _jobs = ((filterRes.data as Map)['jobs'] as List)
          .cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.response?.data?['message']?.toString() ??
                'Nepodařilo se načíst stavby',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }

    try {
      final params = <String, String>{};
      if (_statusFilter != null) params['status'] = _statusFilter!;
      if (_jobIdFilter != null) params['jobId'] = _jobIdFilter!;
      final res = await dio.get(
        '/api/worksheets',
        queryParameters: params.isEmpty ? null : params,
      );
      if (!mounted) return;
      setState(() {
        _worksheets = (res.data as List).cast<Map<String, dynamic>>();
        _loadingWorksheets = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _loadingWorksheets = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.response?.data?['message']?.toString() ??
                'Nepodařilo se načíst soupisy',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _createWorksheetFromFilters() async {
    final reports = _reportsKey.currentState;
    if (reports == null) return;
    final params = reports.queryParams;
    final jobId = params['jobId'];
    if (jobId == null || jobId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vyberte stavbu pro vytvoření soupisu')),
      );
      return;
    }
    try {
      final res = await ref.read(dioProvider).post('/api/worksheets', data: {
        'jobId': jobId,
      });
      final ws = res.data as Map<String, dynamic>;
      final populateBody = <String, dynamic>{};
      if (params['floorId'] != null) {
        populateBody['floorIds'] = [params['floorId']];
      }
      if (params['status'] != null) populateBody['status'] = params['status'];
      if (params['from'] != null) populateBody['from'] = params['from'];
      if (params['to'] != null) populateBody['to'] = params['to'];
      await ref.read(dioProvider).post(
            '/api/worksheets/${ws['id']}/populate',
            data: populateBody,
          );
      await _loadWorksheets();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Formalní soupis vytvořen')),
      );
      context.push('/worksheets/${ws['id']}');
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.response?.data?['message'] ?? 'Chyba')),
      );
    }
  }

  Future<void> _createWorksheetQuick() async {
    if (_jobs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nejdříve vyberte dostupnou zakázku')),
      );
      return;
    }
    String? selectedJobId = _jobs.first['id'] as String?;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nový soupis práce'),
          content: DropdownButtonFormField<String>(
            value: selectedJobId,
            decoration: const InputDecoration(labelText: 'Zakázka'),
            items: _jobs
                .map((j) => DropdownMenuItem(
                      value: j['id'] as String,
                      child: Text('${j['projectNumber']} ${j['name']}'),
                    ))
                .toList(),
            onChanged: (v) => setDialogState(() => selectedJobId = v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Zrušit')),
            FilledButton(
              onPressed: () async {
                if (selectedJobId == null) return;
                Navigator.pop(ctx);
                try {
                  final res = await ref.read(dioProvider).post('/api/worksheets', data: {
                    'jobId': selectedJobId,
                  });
                  final ws = res.data as Map<String, dynamic>;
                  await ref.read(dioProvider).post(
                        '/api/worksheets/${ws['id']}/populate',
                        data: {},
                      );
                  await _loadWorksheets();
                } on DioException catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.response?.data?['message'] ?? 'Chyba')),
                  );
                }
              },
              child: const Text('Vytvořit'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(auth.isWorker ? 'Moje soupisy' : 'Soupisy práce'),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) {
              _statusFilter = v;
              _loadWorksheets();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('Vše')),
              ..._statusLabels.entries.map(
                (e) => PopupMenuItem(value: e.key, child: Text(e.value)),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadWorksheets();
              _reportsKey.currentState?.load();
            },
          ),
        ],
      ),
      floatingActionButton: auth.canCreateWorksheet
          ? FloatingActionButton.extended(
              onPressed: _createWorksheetQuick,
              icon: const Icon(Icons.add),
              label: const Text('Nový soupis'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _loadWorksheets,
        child: CustomScrollView(
          slivers: [
            if (auth.canAccessReports) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: AppCard(
                    showChevron: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SectionHeader(
                          title: 'Nový soupis / Export',
                          style: SectionHeaderStyle.h3,
                        ),
                        ReportsScreen(
                          key: _reportsKey,
                          compact: true,
                          initialJobId: _jobIdFilter,
                          initialStatus: _reportStatusFilter,
                          initialWorkerId: _reportWorkerId,
                        ),
                        AppPrimaryButton(
                          label: 'Vytvořit formalní soupis z filtru',
                          icon: Icons.description,
                          onPressed: auth.canCreateWorksheet
                              ? _createWorksheetFromFilters
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
                child: SectionHeader(
                  title: 'Uložené soupisy',
                  style: SectionHeaderStyle.h3,
                ),
              ),
            ),
            if (_loadingWorksheets)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_worksheets.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  message: 'Žádné soupisy',
                  icon: Icons.description_outlined,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final ws = _worksheets[i];
                      final job = ws['job'] as Map<String, dynamic>?;
                      final status = ws['status'] as String? ?? 'draft';
                      final count = ws['_count']?['items'] ?? 0;
                      final id = ws['id'] as String;
                      return AppCard(
                        title: '${job?['projectNumber'] ?? ''} ${job?['name'] ?? ''}'.trim(),
                        subtitle: '$count položek',
                        trailing: StatusBadge(
                          status: status,
                          label: _statusLabels[status] ?? status,
                          compact: true,
                        ),
                        onTap: () => context.push('/worksheets/$id'),
                      );
                    },
                    childCount: _worksheets.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
