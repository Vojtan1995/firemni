import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../auth/auth_provider.dart';

class SealDetailScreen extends ConsumerStatefulWidget {
  const SealDetailScreen({super.key, required this.sealId});
  final String sealId;

  @override
  ConsumerState<SealDetailScreen> createState() => _SealDetailScreenState();
}

class _SealDetailScreenState extends ConsumerState<SealDetailScreen> {
  Map<String, dynamic>? _seal;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ref.read(dioProvider).get('/api/seals/${widget.sealId}');
    setState(() {
      _seal = res.data as Map<String, dynamic>;
      _loading = false;
    });
  }

  Future<void> _changeStatus(String status) async {
    await ref.read(dioProvider).patch('/api/seals/${widget.sealId}/status', data: {'status': status});
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final seal = _seal!;
    final status = seal['status'] as String;
    final auth = ref.read(authServiceProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Ucpávka #${seal['sealNumber']}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Container(width: 16, height: 16, decoration: BoxDecoration(color: AppTheme.statusColor(status), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(status, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Text('Systém: ${seal['system']}'),
          Text('Konstrukce: ${seal['construction']}'),
          Text('Umístění: ${seal['location']}'),
          Text('Odolnost: ${seal['fireRating']}'),
          if (seal['note'] != null) Text('Poznámka: ${seal['note']}'),
          const Divider(),
          const Text('Prostupy', style: TextStyle(fontWeight: FontWeight.bold)),
          ...(seal['entries'] as List? ?? []).map((e) {
            final m = e as Map<String, dynamic>;
            return ListTile(
              title: Text('${m['entryType']} – ${m['dimension']}'),
              subtitle: Text('${m['quantity']} ks, ${m['insulation']}'),
              trailing: Text((m['materials'] as List?)?.map((x) => (x as Map)['material']).join(', ') ?? ''),
            );
          }),
          const Divider(),
          const Text('Fotky', style: TextStyle(fontWeight: FontWeight.bold)),
          ...(seal['photos'] as List? ?? []).map((p) {
            final m = p as Map<String, dynamic>;
            final url = '${AppConfig.apiBaseUrl}/uploads/${m['filePath']}';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Image.network(url, height: 200, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 100)),
            );
          }),
          if (auth.isManagement) ...[
            const SizedBox(height: 16),
            if (status == 'draft')
              ElevatedButton(onPressed: () => _changeStatus('checked'), child: const Text('Zkontrolovat')),
            if (status == 'checked') ...[
              ElevatedButton(onPressed: () => _changeStatus('invoiced'), child: const Text('Fakturovat')),
              OutlinedButton(onPressed: () => _changeStatus('draft'), child: const Text('Vrátit na rozpracováno')),
            ],
          ],
        ],
      ),
    );
  }
}
