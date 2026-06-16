import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';

const _statusLabels = {
  'draft': 'Rozpracovaný',
  'submitted': 'Odevzdaný',
  'reviewed': 'Schválený',
  'ready_for_invoice': 'Schválený',
  'invoiced': 'Vyfakturovaný',
};

class ProfileWorksheetsSection extends ConsumerStatefulWidget {
  const ProfileWorksheetsSection({super.key, required this.role});

  final String role;

  @override
  ConsumerState<ProfileWorksheetsSection> createState() =>
      _ProfileWorksheetsSectionState();
}

class _ProfileWorksheetsSectionState extends ConsumerState<ProfileWorksheetsSection> {
  List<Map<String, dynamic>> _items = [];
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
      final res = await ref.read(dioProvider).get('/api/worksheets');
      if (!mounted) return;
      setState(() {
        _items = (res.data as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e, fallback: 'Nepodařilo se načíst soupisy');
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Nepodařilo se načíst soupisy';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: SectionHeader(title: 'Moje soupisy', style: SectionHeaderStyle.h3),
            ),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Text(_error!, style: const TextStyle(color: AppColors.error))
        else if (_items.isEmpty)
          const Text('Zatím nemáte žádné soupisy.')
        else
          ..._items.take(20).map((ws) {
            final job = ws['job'] as Map<String, dynamic>?;
            final status = ws['status'] as String? ?? 'draft';
            final id = ws['id'] as String;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                title: job?['name']?.toString() ?? 'Soupis',
                subtitle:
                    '${job?['projectNumber'] ?? ''} · ${_statusLabels[status] ?? status}',
                trailing: StatusBadge(
                  status: status,
                  label: _statusLabels[status] ?? status,
                ),
                onTap: () => context.push('/worksheets/$id'),
              ),
            );
          }),
      ],
    );
  }
}
