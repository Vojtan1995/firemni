import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

class PrivacyNoticeGate extends StatefulWidget {
  const PrivacyNoticeGate({
    super.key,
    required this.dio,
    required this.userId,
    required this.child,
  });

  final Dio dio;
  final String? userId;
  final Widget child;

  @override
  State<PrivacyNoticeGate> createState() => _PrivacyNoticeGateState();
}

class _PrivacyNoticeGateState extends State<PrivacyNoticeGate> {
  String? _checkedUserId;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didUpdateWidget(covariant PrivacyNoticeGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    final userId = widget.userId;
    if (!mounted || userId == null || _checkedUserId == userId || _checking) {
      return;
    }
    _checking = true;
    try {
      final response = await widget.dio.get('/api/privacy/notice');
      final data = Map<String, dynamic>.from(response.data as Map);
      _checkedUserId = userId;
      if (data['accepted'] == true || !mounted) return;
      await _showNotice(data);
    } catch (_) {
      // Nedostupná síť nesmí zablokovat již přihlášenou offline práci.
    } finally {
      _checking = false;
    }
  }

  Future<void> _showNotice(Map<String, dynamic> notice) async {
    final version = notice['version'] as String;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Informace o zpracování osobních údajů'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Verze: $version'),
              const SizedBox(height: 12),
              const Text(
                'Aplikace eviduje pracovní účet, aktivitu, technické záznamy, '
                'fotografie, zprávy a bezpečnostní logy pro provoz, audit a '
                'dokumentaci požárních ucpávek. Nefotografujte osoby, doklady '
                'ani jiné osobní údaje, pokud to není pro práci nezbytné.',
              ),
              if (notice['url'] != null) ...[
                const SizedBox(height: 12),
                SelectableText('Úplné informace: ${notice['url']}'),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              await widget.dio.post(
                '/api/privacy/notice/accept',
                data: {'version': version},
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Beru na vědomí'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
