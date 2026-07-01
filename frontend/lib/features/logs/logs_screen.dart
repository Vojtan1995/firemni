import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import 'backup_status.dart';

/// Definice jedné sekce (tabu) logů – nadpis, endpoint a zda jde o systémové záznamy.
class _LogSection {
  const _LogSection({
    required this.label,
    required this.endpoint,
    this.queryParameters = const {},
    this.isSystem = false,
  });
  final String label;
  final String endpoint;
  final Map<String, String> queryParameters;
  final bool isSystem;
}

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabs;
  late List<_LogSection> _sections;
  final Map<String, List<Map<String, dynamic>>> _data = {};
  BackupStatusSummary? _backupStatus;
  bool _loading = true;
  int _sinceDays = 7;

  static const _dayFormat = 'yyyy-MM-dd';

  @override
  void initState() {
    super.initState();
    // Sekce se odvodí podle role v didChangeDependencies (potřebuje ref).
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  void _init() {
    final auth = ref.read(authServiceProvider);
    final sections = <_LogSection>[
      if (auth.canViewLogs)
        const _LogSection(
          label: 'Ucpávky',
          endpoint: '/api/logs/history',
          queryParameters: {
            'entityType': 'seal',
            'excludeCategory': 'Fotky a výkresy',
          },
        ),
      if (auth.canViewLogs)
        const _LogSection(
          label: 'Soupisy',
          endpoint: '/api/logs/history',
          queryParameters: {'entityType': 'worksheet'},
        ),
      if (auth.canViewLogs)
        const _LogSection(
          label: 'Stavby a patra',
          endpoint: '/api/logs/history',
          queryParameters: {
            'entityTypes': 'job,job_floor',
            'excludeCategory': 'Fotky a výkresy',
          },
        ),
      if (auth.canViewLogs)
        const _LogSection(
          label: 'Fotky/výkresy',
          endpoint: '/api/logs/history',
          queryParameters: {'category': 'Fotky a výkresy'},
        ),
      if (auth.canViewLogs)
        const _LogSection(
          label: 'Uživatelé/práva',
          endpoint: '/api/logs/user-activity',
        ),
      if (auth.isAdmin)
        const _LogSection(
          label: 'Zálohy',
          endpoint: '/api/logs/backups',
          isSystem: true,
        ),
      if (auth.isAdmin)
        const _LogSection(
          label: 'Systém/sync',
          endpoint: '/api/logs/system',
          isSystem: true,
        ),
    ];
    setState(() {
      _sections = sections;
      _tabs = TabController(length: sections.length, vsync: this);
    });
    _load();
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dio = ref.read(dioProvider);
    final since = DateTime.now()
        .subtract(Duration(days: _sinceDays))
        .toUtc()
        .toIso8601String();
    try {
      await Future.wait(_sections.map((s) async {
        final res = await dio.get(
          s.endpoint,
          queryParameters: {'since': since, ...s.queryParameters},
        );
        _data[s.label] = (res.data as List).cast<Map<String, dynamic>>();
      }));
      if (ref.read(authServiceProvider).isAdmin) {
        final statusRes = await dio.get('/api/admin/backup-status');
        _backupStatus = BackupStatusSummary.fromJson(
          Map<String, dynamic>.from(statusRes.data as Map),
        );
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _openEntity(Map<String, dynamic>? entity) {
    if (entity == null) return;
    final id = entity['id'] as String?;
    if (id == null || id.isEmpty) return;
    switch (entity['type']) {
      case 'seal':
        context.push('/seal/$id');
        break;
      case 'job':
        context.push('/floors/$id');
        break;
      case 'job_floor':
        context.push('/seals/$id');
        break;
      case 'worksheet':
        context.push('/worksheets/$id');
        break;
      case 'user':
        if (ref.read(authServiceProvider).canManageUsers) {
          context.push('/users-admin');
        }
        break;
    }
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Dnes';
    if (diff == 1) return 'Včera';
    return DateFormat('d.M.y').format(d);
  }

  DateTime? _parseTs(dynamic ts) =>
      ts is String ? DateTime.tryParse(ts)?.toLocal() : null;

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    if (tabs == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Logy')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logy'),
        bottom: TabBar(
          controller: tabs,
          isScrollable: true,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.accent,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: AppColors.border,
          labelStyle: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
          unselectedLabelStyle: Theme.of(context).textTheme.bodyMedium,
          tabs: _sections.map((s) => Tab(text: s.label)).toList(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          _rangeBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: tabs,
                    children: _sections.map(_sectionView).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _rangeBar() {
    Widget chip(String label, int days) => Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sm),
          child: ChoiceChip(
            label: Text(label),
            selected: _sinceDays == days,
            onSelected: (_) {
              setState(() => _sinceDays = days);
              _load();
            },
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [chip('Dnes', 1), chip('7 dní', 7), chip('30 dní', 30)],
      ),
    );
  }

  /// Pořadí podkategorií v UI (české, bez syrových názvů akcí).
  static const _categoryOrder = [
    'Vytvořené',
    'Stav',
    'Úpravy',
    'Přesuny',
    'Fotky a výkresy',
    'Smazání a obnova',
    'Ceník',
    'Ostatní',
  ];

  List<Widget> _dayGroupedChildren(
    List<Map<String, dynamic>> items, {
    required bool isSystem,
  }) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final ts = _parseTs(item['timestamp']);
      final key = ts != null ? DateFormat(_dayFormat).format(ts) : 'starší';
      groups.putIfAbsent(key, () => []).add(item);
    }
    final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    final children = <Widget>[];
    for (final key in keys) {
      final first = _parseTs(groups[key]!.first['timestamp']);
      children.add(SectionHeader(
        title: first != null ? _dayLabel(first) : 'Starší',
        style: SectionHeaderStyle.h3,
      ));
      for (final item in groups[key]!) {
        children.add(isSystem ? _systemRow(item) : _historyRow(item));
      }
    }
    return children;
  }

  Widget _sectionView(_LogSection section) {
    final items = _data[section.label] ?? const [];
    final isBackupSection = section.endpoint == '/api/logs/backups';
    if (items.isEmpty && !(isBackupSection && _backupStatus != null)) {
      return const EmptyState(message: 'Žádné záznamy', icon: Icons.history);
    }

    if (section.isSystem) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (isBackupSection) ..._backupStatusChildren(),
            if (items.isNotEmpty) ..._dayGroupedChildren(items, isSystem: true),
          ],
        ),
      );
    }

    // Seskupení podle podkategorie (Vytvořené/Stav/Úpravy/Přesuny/…), uvnitř po dnech.
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final category = item['category'] as String? ?? 'Ostatní';
      byCategory.putIfAbsent(category, () => []).add(item);
    }
    final categories = byCategory.keys.toList()
      ..sort((a, b) {
        final ia = _categoryOrder.indexOf(a);
        final ib = _categoryOrder.indexOf(b);
        return (ia == -1 ? _categoryOrder.length : ia)
            .compareTo(ib == -1 ? _categoryOrder.length : ib);
      });

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          for (final category in categories)
            Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ExpansionTile(
                title: Text(
                  category,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('${byCategory[category]!.length} záznamů'),
                initiallyExpanded: categories.length == 1,
                childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
                children:
                    _dayGroupedChildren(byCategory[category]!, isSystem: false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _historyRow(Map<String, dynamic> item) {
    final entity = item['entity'] as Map<String, dynamic>?;
    final user = item['user'] as Map<String, dynamic>?;
    final ts = _parseTs(item['timestamp']);
    final time = ts != null ? DateFormat('HH:mm').format(ts) : '';
    final who = user?['displayName'] as String?;
    final subtitle =
        [who, time].where((e) => e != null && e.isNotEmpty).join(' · ');
    return AppCard(
      title: item['title'] as String? ?? '',
      subtitle: subtitle.isEmpty ? null : subtitle,
      showChevron: entity != null,
      onTap: entity != null ? () => _openEntity(entity) : null,
    );
  }

  Widget _systemRow(Map<String, dynamic> item) {
    final ts = _parseTs(item['timestamp']);
    final time = ts != null ? DateFormat('HH:mm').format(ts) : '';
    final detail = item['detail'] as String?;
    final kind = item['kind'] as String?;
    final title = item['title'] as String? ?? '';
    final backupFailed = kind == 'backup' && title.toLowerCase().contains('selhalo');
    final color = switch (kind) {
      'error' => AppColors.error,
      'backup' => backupFailed ? AppColors.error : AppColors.success,
      _ => AppColors.textMuted,
    };
    return AppCard(
      showChevron: false,
      leading: AppIconBox(
        icon: switch (kind) {
          'error' => Icons.error_outline,
          'sync' => Icons.sync,
          'backup' => Icons.backup_outlined,
          _ => Icons.info_outline,
        },
        backgroundColor: color.withValues(alpha: 0.12),
        color: color,
      ),
      title: title,
      subtitle:
          [detail, time].where((e) => e != null && e.isNotEmpty).join(' · '),
    );
  }

  List<Widget> _backupStatusChildren() {
    final status = _backupStatus;
    if (status == null) return const [];
    return [
      const SectionHeader(title: 'Aktuální stav', style: SectionHeaderStyle.h3),
      ...status.checks.map(_backupCheckCard),
      const SizedBox(height: AppSpacing.sm),
      const SectionHeader(title: 'Historie', style: SectionHeaderStyle.h3),
    ];
  }

  Widget _backupCheckCard(BackupHealthCheck check) {
    final color = switch (check.status) {
      'ok' => AppColors.success,
      'stale' => AppColors.warning,
      'failed' => AppColors.error,
      _ => AppColors.textMuted,
    };
    final detail = [
      check.message,
      'stáří ${check.ageLabel}',
      if (check.sizeLabel.isNotEmpty) check.sizeLabel,
      if (check.objectCount != null) '${check.objectCount} objektů',
      check.r2Prefix,
      check.errorMessage,
    ].where((e) => e != null && e.isNotEmpty).join(' Â· ');
    final githubRunUrl = check.githubRunUrl;
    return AppCard(
      leading: AppIconBox(
        icon: switch (check.status) {
          'ok' => Icons.check_circle_outline,
          'stale' => Icons.schedule,
          'failed' => Icons.error_outline,
          _ => Icons.help_outline,
        },
        backgroundColor: color.withValues(alpha: 0.12),
        color: color,
      ),
      title: '${check.title}: ${check.statusLabel}',
      subtitle: detail,
      showChevron: githubRunUrl != null,
      onTap: githubRunUrl == null
          ? null
          : () async {
              await launchUrl(
                Uri.parse(githubRunUrl),
                mode: LaunchMode.externalApplication,
              );
            },
    );
  }
}
