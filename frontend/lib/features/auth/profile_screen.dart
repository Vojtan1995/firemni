import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_service.dart';
import 'auth_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  Future<void> _changePin() async {
    final newPin = _newCtrl.text;
    if (newPin.length < 4 || newPin.length > 8) {
      setState(() {
        _error = 'Nový PIN musí mít 4 až 8 číslic';
        _success = null;
      });
      return;
    }
    if (newPin != _confirmCtrl.text) {
      setState(() {
        _error = 'Nový PIN a potvrzení se neshodují';
        _success = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      await ref.read(authServiceProvider).changePin(_currentCtrl.text, newPin);
      await ref.read(syncServiceProvider).syncAll();
      _currentCtrl.clear();
      _newCtrl.clear();
      _confirmCtrl.clear();
      setState(() => _success = 'PIN byl úspěšně změněn');
    } catch (_) {
      setState(() => _error = 'PIN se nepodařilo změnit — zkontrolujte aktuální PIN');
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
    final user = ref.watch(authUserProvider)!;
    final role = user['role'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(user['displayName'] as String? ?? ''),
              subtitle: Text('${user['username']} · $role'),
            ),
            const Divider(height: 32),
            Text('Změna PINu', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Zadejte starý PIN, nový PIN a jeho potvrzení.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('profile_pin_current'),
              controller: _currentCtrl,
              decoration: const InputDecoration(
                labelText: 'Aktuální PIN',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('profile_pin_new'),
              controller: _newCtrl,
              decoration: const InputDecoration(
                labelText: 'Nový PIN',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('profile_pin_confirm'),
              controller: _confirmCtrl,
              decoration: const InputDecoration(
                labelText: 'Potvrdit nový PIN',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _changePin(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_success != null) ...[
              const SizedBox(height: 12),
              Text(_success!, style: TextStyle(color: Colors.green.shade700)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('profile_pin_submit'),
              onPressed: _loading ? null : _changePin,
              child: _loading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Uložit nový PIN'),
            ),
          ],
        ),
      ),
    );
  }
}
