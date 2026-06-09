import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../database/database_provider.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import 'search_service.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<SearchHit> _hits = [];
  bool _loading = false;
  bool _offline = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.removeListener(_onQueryChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _ctrl.text.trim();
    if (q.length < 2) {
      setState(() {
        _hits = [];
        _error = null;
        _offline = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await ref.read(dioProvider).get(
        '/api/search',
        queryParameters: {'q': q, 'limit': 25},
      );
      final items = (res.data['items'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map(SearchHit.fromApi)
          .toList();
      if (!mounted) return;
      setState(() {
        _hits = items;
        _offline = false;
        _loading = false;
      });
    } on DioException catch (_) {
      final userId = ref.read(currentUserIdProvider);
      final hits = await searchLocal(
        ref.read(databaseProvider),
        query: q,
        userId: userId,
        isWorker: ref.read(authServiceProvider).isWorker,
      );
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _offline = true;
        _loading = false;
        _error = hits.isEmpty ? 'Žádné výsledky v lokální cache' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _openHit(SearchHit hit) {
    switch (hit.type) {
      case 'job':
        context.push('/floors/${hit.id}');
      case 'seal':
        context.push('/seal/${hit.id}');
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vyhledávání'),
        actions: [
          if (_offline)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: Center(child: OfflineIndicator(compact: true)),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Číslo ucpávky, zakázka, patro, systém…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
              ),
            ),
          Expanded(
            child: _hits.isEmpty && !_loading
                ? EmptyState(
                    message: _ctrl.text.trim().length < 2
                        ? 'Zadejte alespoň 2 znaky'
                        : 'Žádné výsledky',
                    icon: Icons.search_off,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: _hits.length,
                    itemBuilder: (_, i) {
                      final hit = _hits[i];
                      return AppCard(
                        leading: AppIconBox(
                          icon: hit.type == 'job'
                              ? Icons.apartment
                              : Icons.inventory_2_outlined,
                        ),
                        title: hit.type == 'job'
                            ? (hit.jobName ?? hit.projectNumber ?? hit.id)
                            : '#${hit.sealNumber ?? '?'}',
                        subtitle: hit.subtitle,
                        onTap: () => _openHit(hit),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
