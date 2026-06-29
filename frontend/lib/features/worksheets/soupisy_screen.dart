import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/design_tokens.dart';
import '../../widgets/app_top_actions.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../reports/reports_screen.dart';

/// Hub pro export a vytváření soupisů ze stejných filtrů.
class SoupisyScreen extends ConsumerStatefulWidget {
  const SoupisyScreen({super.key});

  @override
  ConsumerState<SoupisyScreen> createState() => _SoupisyScreenState();
}

class _SoupisyScreenState extends ConsumerState<SoupisyScreen> {
  final _reportsKey = GlobalKey<ReportsScreenState>();
  final _dateFmt = DateFormat('yyyy-MM-dd');
  String? _jobIdFilter;
  String? _reportStatusFilter;
  String? _reportWorkerId;
  bool _queryParamsApplied = false;
  bool _creatingWorksheet = false;

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

  String _dateParam(DateTime date) => _dateFmt.format(date);

  Future<void> _createWorksheetFromFilters(
    ReportsFilterSelection filters,
  ) async {
    if (filters.jobId == null || filters.jobId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nejdříve vyberte zakázku')),
      );
      return;
    }

    final auth = ref.read(authServiceProvider);
    if (!auth.isWorker && filters.workerIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nejdříve vyberte alespoň jednoho pracovníka'),
        ),
      );
      return;
    }

    setState(() => _creatingWorksheet = true);
    try {
      // 1 soupis = 1 zakázka = 1 worker. Pro "pro pracovníka" + více workerů
      // backend vytvoří soupis pro každého zvlášť; pro "pro zákazníka" jeden
      // soupis se všemi jmény. Vše řeší endpoint /generate jedním voláním.
      final body = <String, dynamic>{
        'jobId': filters.jobId,
        'audience': filters.audience,
        if (filters.floorIds.isNotEmpty) 'floorIds': filters.floorIds,
        if (filters.status != null) 'status': filters.status,
        if (filters.from != null) 'periodFrom': _dateParam(filters.from!),
        if (filters.to != null) 'periodTo': _dateParam(filters.to!),
        if (filters.from != null) 'from': _dateParam(filters.from!),
        if (filters.to != null) 'to': _dateParam(filters.to!),
      };
      if (!auth.isWorker) body['workerIds'] = filters.workerIds;

      final res = await ref.read(dioProvider).post(
            '/api/worksheets/generate',
            data: body,
          );

      if (!mounted) return;
      final results =
          (res.data as Map<String, dynamic>)['worksheets'] as List? ?? [];
      final totalAdded = results.fold<int>(
        0,
        (sum, r) =>
            sum + (((r as Map)['addedCount'] as num?)?.toInt() ?? 0),
      );

      if (results.length == 1) {
        final r = results.first as Map<String, dynamic>;
        final ws = r['worksheet'] as Map<String, dynamic>;
        final requested = (r['requestedCount'] as num?)?.toInt();
        final added = (r['addedCount'] as num?)?.toInt();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              requested != null && added != null
                  ? 'Soupis vytvořen. Přidáno $added z $requested položek.'
                  : 'Soupis vytvořen.',
            ),
          ),
        );
        context.push('/worksheets/${ws['id']}');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Vytvořeno ${results.length} soupisů. Přidáno celkem '
              '$totalAdded položek.',
            ),
          ),
        );
        context.push('/saved-worksheets');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e, fallback: 'Chyba'))),
      );
    } finally {
      if (mounted) setState(() => _creatingWorksheet = false);
    }
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
            onPressed: () => _reportsKey.currentState?.refreshFilterOptions(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (auth.canAccessReports)
            AppCard(
              showChevron: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(
                    title: 'Vytvoření soupisu',
                    style: SectionHeaderStyle.h3,
                  ),
                  ReportsScreen(
                    key: _reportsKey,
                    compact: true,
                    hideLoadButton: true,
                    initialJobId: _jobIdFilter,
                    initialStatus: _reportStatusFilter,
                    initialWorkerId: _reportWorkerId,
                    onCreateWorksheet: auth.canCreateWorksheet
                        ? _createWorksheetFromFilters
                        : null,
                    worksheetActionLoading: _creatingWorksheet,
                  ),
                ],
              ),
            ),
          if (auth.canAccessReports) const SizedBox(height: AppSpacing.lg),
          AppSecondaryButton(
            label: auth.isWorker
                ? 'Zobrazit uložené soupisy'
                : 'Uložené soupisy',
            icon: auth.isWorker
                ? Icons.folder_open_outlined
                : Icons.people_outline,
            onPressed: () => context.push('/saved-worksheets'),
          ),
        ],
      ),
    );
  }
}
