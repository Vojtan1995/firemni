import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  bool _inbox = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final msgRes = await dio.get(
        '/api/messages',
        queryParameters: {'box': _inbox ? 'inbox' : 'sent'},
      );
      _messages = (msgRes.data as List).cast<Map<String, dynamic>>();
      if (_users.isEmpty) {
        final contactsRes = await dio.get('/api/messages/contacts');
        _users = (contactsRes.data as List).cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _compose() async {
    if (_users.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seznam příjemců není k dispozici')),
      );
      return;
    }
    final bodyCtrl = TextEditingController();
    var recipientId = _users.first['id'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: const Text('Nová zpráva'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: recipientId,
                decoration: const InputDecoration(labelText: 'Příjemce'),
                items: _users
                    .map((u) => DropdownMenuItem(
                          value: u['id'] as String,
                          child: Text(u['displayName'] as String? ?? ''),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialog(() => recipientId = v);
                },
              ),
              TextField(
                controller: bodyCtrl,
                decoration: const InputDecoration(labelText: 'Text zprávy'),
                maxLines: 4,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Zrušit')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Odeslat')),
          ],
        ),
      ),
    );
    if (ok != true || bodyCtrl.text.trim().isEmpty) return;
    try {
      await ref.read(dioProvider).post('/api/messages', data: {
        'recipientId': recipientId,
        'body': bodyCtrl.text.trim(),
      });
      setState(() => _inbox = false);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zprávu se nepodařilo odeslat')),
        );
      }
    }
  }

  Future<void> _markRead(String id) async {
    try {
      await ref.read(dioProvider).patch('/api/messages/$id/read');
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_inbox ? 'Doručené zprávy' : 'Odeslané zprávy'),
        actions: [
          IconButton(
            icon: Icon(_inbox ? Icons.outbox : Icons.inbox),
            tooltip: _inbox ? 'Odeslané' : 'Doručené',
            onPressed: () {
              setState(() => _inbox = !_inbox);
              _load();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _compose,
        child: const Icon(Icons.edit),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _messages.isEmpty
              ? const EmptyState(message: 'Žádné zprávy', icon: Icons.mail_outline)
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final m = _messages[i];
                    final sender = m['sender'] as Map<String, dynamic>?;
                    final recipient = m['recipient'] as Map<String, dynamic>?;
                    final isUnread = _inbox && m['readAt'] == null;
                    final peer = _inbox ? sender : recipient;
                    return AppCard(
                      showChevron: false,
                      borderColor: isUnread
                          ? AppColors.info.withValues(alpha: 0.4)
                          : null,
                      leading: AppIconBox(
                        icon: isUnread ? Icons.mark_email_unread : Icons.mail_outline,
                        color: isUnread ? AppColors.info : AppColors.textSecondary,
                        backgroundColor: (isUnread ? AppColors.info : AppColors.textMuted)
                            .withValues(alpha: 0.12),
                        size: 40,
                      ),
                      title: peer?['displayName'] as String? ?? '',
                      subtitle: m['body'] as String? ?? '',
                      onTap: () {
                        if (_inbox && m['readAt'] == null) {
                          _markRead(m['id'] as String);
                        }
                      },
                    );
                  },
                ),
    );
  }
}
