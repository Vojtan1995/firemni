import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';
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
    if (newPin.length < 6 || newPin.length > 8) {
      setState(() => _error = 'Nový PIN musí mít 6 až 8 číslic');
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
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              Text(
                'Nastavte si vlastní PIN',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Před pokračováním je potřeba změnit dočasný PIN.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              AppTextField(
                key: const Key('change_pin_current'),
                controller: _currentCtrl,
                label: 'Aktuální PIN',
                obscureText: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                prefixIcon: const Icon(Icons.lock_outline),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                key: const Key('change_pin_new'),
                controller: _newCtrl,
                label: 'Nový PIN',
                obscureText: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                prefixIcon: const Icon(Icons.lock_reset),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                key: const Key('change_pin_confirm'),
                controller: _confirmCtrl,
                label: 'Potvrdit nový PIN',
                obscureText: true,
                keyboardType: TextInputType.number,
                prefixIcon: const Icon(Icons.check_circle_outline),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: AppSpacing.xl),
              AppPrimaryButton(
                key: const Key('change_pin_submit'),
                label: 'Uložit PIN',
                loading: _loading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
