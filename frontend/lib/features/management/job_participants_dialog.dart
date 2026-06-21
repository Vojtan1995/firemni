import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';

/// Dialog pro přiřazování pracovníků (worker) k zakázce – pouze vedení/admin.
/// Odebrání pracovníka NEMAŽE jeho ucpávky/soupisy/historii, jen mu odebere
/// přístup k zakázce do budoucna.
class JobParticipantsDialog extends ConsumerStatefulWidget {
  const JobParticipantsDialog({
    super.key,
    required this.jobId,
    required this.jobLabel,
  });

  final String jobId;
  final String jobLabel;

  static Future<void> show(
    BuildContext context, {
    required String jobId,
    required String jobLabel,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => JobParticipantsDialog(jobId: jobId, jobLabel: jobLabel),
    );
  }

  @override
  ConsumerState<JobParticipantsDialog> createState() =>
      _JobParticipantsDialogState();
}

class _JobParticipantsDialogState extends ConsumerState<JobParticipantsDialog> {
  bool _loading = true;
  String? _error;
  bool _saving = false;
  List<Map<String, dynamic>> _participants = [];
  List<Map<String, dynamic>> _workers = [];

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
      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        dio.get('/api/jobs/${widget.jobId}/participants'),
        dio.get('/api/users'),
      ]);
      if (!mounted) return;
      final participants =
          (results[0].data as List).cast<Map<String, dynamic>>();
      final allUsers = (results[1].data as List).cast<Map<String, dynamic>>();
      setState(() {
        _participants = participants;
        _workers =
            allUsers.where((u) => u['role'] == 'worker').toList(growable: false);
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(e, fallback: 'Nepodařilo se načíst pracovníky');
      });
    }
  }

  Future<void> _addWorker(Map<String, dynamic> worker) async {
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).post(
        '/api/jobs/${widget.jobId}/participants',
        data: {'userId': worker['id'], 'roleOnJob': 'worker'},
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e, fallback: 'Přidání selhalo'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeWorker(Map<String, dynamic> participant) async {
    final sealCount = (participant['sealCount'] as num?)?.toInt() ?? 0;
    final name = participant['displayName'] as String? ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Odebrat $name?'),
        content: Text(
          sealCount > 0
              ? 'Tento pracovník už má na zakázce vytvořené ucpávky. Odebráním se '
                  'jeho práce nesmaže, pouze ztratí přístup k zakázce.'
              : 'Pracovník ztratí přístup k zakázce. Jeho práce zůstane zachována.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Zrušit')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Odebrat')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).delete(
            '/api/jobs/${widget.jobId}/participants/${participant['userId']}',
          );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e, fallback: 'Odebrání selhalo'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final assignedIds =
        _participants.map((p) => p['userId'] as String).toSet();
    final available = _workers
        .where((w) => !assignedIds.contains(w['id']))
        .toList(growable: false);

    return AlertDialog(
      title: Text('Pracovníci – ${widget.jobLabel}'),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
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
                : _buildBody(available),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Zavřít'),
        ),
      ],
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> available) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Autocomplete pro přidání pracovníka podle jména.
        Autocomplete<Map<String, dynamic>>(
          displayStringForOption: (o) => o['displayName'] as String? ?? '',
          optionsBuilder: (value) {
            final q = value.text.trim().toLowerCase();
            if (q.isEmpty) return available;
            return available.where((w) {
              final name = (w['displayName'] as String? ?? '').toLowerCase();
              final username = (w['username'] as String? ?? '').toLowerCase();
              return name.contains(q) || username.contains(q);
            });
          },
          fieldViewBuilder: (ctx, controller, focusNode, onSubmit) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(
                labelText: 'Najít pracovníka podle jména',
                prefixIcon: Icon(Icons.search),
              ),
            );
          },
          onSelected: _saving ? (_) {} : _addWorker,
        ),
        const SizedBox(height: AppSpacing.md),
        if (_participants.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text('Zatím není přiřazen žádný pracovník'),
          )
        else
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: _participants.map((p) {
                final sealCount = (p['sealCount'] as num?)?.toInt() ?? 0;
                final username = p['username'] as String?;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(p['displayName'] as String? ?? ''),
                  subtitle: Text(
                    [
                      if (username != null && username.isNotEmpty) username,
                      '$sealCount ucpávek',
                    ].join(' · '),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: 'Odebrat',
                    onPressed: _saving ? null : () => _removeWorker(p),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
