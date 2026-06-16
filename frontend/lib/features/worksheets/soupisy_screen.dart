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
import '../reports/reports_screen.dart';
import 'worksheet_create_helpers.dart';

/// Export soupisu; uložené soupisy jsou na samostatné obrazovce.
class SoupisyScreen extends ConsumerStatefulWidget {
  const SoupisyScreen({super.key});

  @override
  ConsumerState<SoupisyScreen> createState() => _SoupisyScreenState();
}

class _SoupisyScreenState extends ConsumerState<SoupisyScreen> {
  final _reportsKey = GlobalKey<ReportsScreenState>();
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _workers = [];
  String? _jobIdFilter;
  String? _reportStatusFilter;
  String? _reportWorkerId;
  bool _queryParamsApplied = false;

  @override
  void initState() {
    super.initState();
    _loadFilterOptions();
  }

  Future<void> _loadFilterOptions() async {
    try {
      final filterRes = await ref.read(dioProvider).get('/api/reports/filter-options');
      if (!mounted) return;
      setState(() {
        _jobs = ((filterRes.data as Map)['jobs'] as List)
            .cast<Map<String, dynamic>>();
        _workers = ((filterRes.data as Map)['workers'] as List? ?? [])
            .cast<Map<String, dynamic>>();
      });
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            apiErrorMessage(e, fallback: 'Nepodařilo se načíst filtry'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_queryParamsApplied) return;
    _queryParamsApplied = true;
    final qp = GoRouterState.of(context).uri.queryParameters;
    final jobId = qp['jobId'];
    final reportStatus = qp['reportStatus'];
    final workerId = qp['workerId'];
    if (jobId != null || reportStatus != null || workerId != null) {
      _jobIdFilter = jobId;
      _reportStatusFilter = reportStatus;
      _reportWorkerId = workerId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reportsKey.currentState?.applyInitialFilters(
          jobId: jobId,
          status: reportStatus,
          workerId: workerId,
        );
      });
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
            key: ValueKey(selectedJobId),
            initialValue: selectedJobId,
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
                  final auth = ref.read(authServiceProvider);
                  List<String>? workerIds;
                  if (!auth.isWorker) {
                    workerIds = await pickWorksheetWorkerIds(
                      ctx,
                      workers: _workers,
                    );
                    if (workerIds == null || workerIds.isEmpty) return;
                  }

                  final body = <String, dynamic>{'jobId': selectedJobId};
                  if (workerIds != null) body['workerIds'] = workerIds;

                  final res = await ref.read(dioProvider).post('/api/worksheets', data: body);
                  final ws = res.data as Map<String, dynamic>;
                  final popRes = await ref.read(dioProvider).post(
                        '/api/worksheets/${ws['id']}/populate',
                        data: {},
                      );
                  if (!mounted) return;
                  final pop = popRes.data as Map<String, dynamic>?;
                  final requested = (pop?['requestedCount'] as num?)?.toInt();
                  final added = (pop?['addedCount'] as num?)?.toInt();
                  if (requested != null &&
                      added != null &&
                      requested > added) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Do soupisu bylo přidáno $added z $requested položek. '
                          '${requested - added} je již součástí jiného soupisu.',
                        ),
                      ),
                    );
                  }
                } on DioException catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(apiErrorMessage(e, fallback: 'Chyba'))),
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
          const AppTopActions(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFilterOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (auth.canAccessReports)
                  AppCard(
                    showChevron: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SectionHeader(
                          title: 'Export soupisu',
                          style: SectionHeaderStyle.h3,
                        ),
                        ReportsScreen(
                          key: _reportsKey,
                          compact: true,
                          hideLoadButton: true,
                          initialJobId: _jobIdFilter,
                          initialStatus: _reportStatusFilter,
                          initialWorkerId: _reportWorkerId,
                        ),
                      ],
                    ),
                  ),
                if (auth.canAccessReports) const SizedBox(height: AppSpacing.lg),
                AppSecondaryButton(
                  label: auth.isWorker
                      ? 'Zobrazit uložené soupisy'
                      : 'Soupisy podle pracovníků',
                  icon: auth.isWorker
                      ? Icons.folder_open_outlined
                      : Icons.people_outline,
                  onPressed: () => context.push('/saved-worksheets'),
                ),
              ],
            ),
          ),
          if (auth.canCreateWorksheet)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: AppPrimaryButton(
                  label: 'Nový soupis',
                  icon: Icons.add,
                  onPressed: _createWorksheetQuick,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
