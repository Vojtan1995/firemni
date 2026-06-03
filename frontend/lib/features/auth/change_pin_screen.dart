import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../sync/sync_service.dart';
import 'auth_provider.dart';

class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});

  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    final newPin = _newCtrl.text;
    if (newPin.length < 4 || newPin.length > 8) {
      setState(() => _error = 'Nový PIN musí mít 4 až 8 číslic');
      return;
    }
    if (newPin != _confirmCtrl.text) {
      setState(() => _error = 'Nový PIN a potvrzení se neshodují');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).changePin(_currentCtrl.text, newPin);
      await ref.read(syncServiceProvider).syncAll();
      if (mounted) context.go('/');
    } catch (_) {
      setState(() => _error = 'PIN se nepodařilo změnit');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Změna PINu'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Nastavte si vlastní PIN',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Před pokračováním je potřeba změnit dočasný PIN.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              TextField(
                key: const Key('change_pin_current'),
                controller: _currentCtrl,
                decoration: const InputDecoration(
                    labelText: 'Aktuální PIN', border: OutlineInputBorder()),
                obscureText: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('change_pin_new'),
                controller: _newCtrl,
                decoration: const InputDecoration(
                    labelText: 'Nový PIN', border: OutlineInputBorder()),
                obscureText: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('change_pin_confirm'),
                controller: _confirmCtrl,
                decoration: const InputDecoration(
                    labelText: 'Potvrdit nový PIN',
                    border: OutlineInputBorder()),
                obscureText: true,
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('change_pin_submit'),
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Uložit PIN'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
