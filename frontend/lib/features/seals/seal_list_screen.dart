import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/theme.dart';

class SealListScreen extends ConsumerStatefulWidget {
  const SealListScreen({super.key, required this.floorId, required this.jobId});
  final String floorId;
  final String jobId;

  @override
  ConsumerState<SealListScreen> createState() => _SealListScreenState();
}

class _SealListScreenState extends ConsumerState<SealListScreen> {
  List<Map<String, dynamic>> _seals = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ref.read(dioProvider).get('/api/seals/floors/${widget.floorId}/seals');
    setState(() {
      _seals = (res.data as List).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ucpávky na patře')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/seal/new?jobId=${widget.jobId}&floorId=${widget.floorId}'),
        icon: const Icon(Icons.add),
        label: const Text('Nová'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 1.2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _seals.length,
              itemBuilder: (_, i) {
                final s = _seals[i];
                final status = s['status'] as String? ?? 'draft';
                return InkWell(
                  onTap: () {
                    context.push('/seal/${s['id']}').then((_) => _load());
                  },
                  child: Card(
                    color: AppTheme.statusColor(status).withValues(alpha: 0.2),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: AppTheme.statusColor(status),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            s['sealNumber'] as String,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
