import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';
import 'auth_provider.dart';
import '../sync/sync_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .login(_userCtrl.text.trim(), _pinCtrl.text);
      final mustChangePin =
          ref.read(authUserProvider)?['mustChangePin'] == true;
      if (mustChangePin) {
        if (mounted) context.go('/change-pin');
        return;
      }
      await ref.read(syncServiceProvider).syncAll();
      if (mounted) context.go('/');
    } catch (e) {
      setState(() => _error = 'Neplatné přihlašovací údaje');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xxl),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: AppRadius.lgAll,
                  ),
                  child: const Icon(Icons.shield_outlined, size: 36, color: AppColors.accent),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Ucpávky',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Přihlášení jménem a PIN',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xxl),
              AppTextField(
                key: const Key('login_username'),
                controller: _userCtrl,
                label: 'Uživatelské jméno',
                textInputAction: TextInputAction.next,
                prefixIcon: const Icon(Icons.person_outline),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                key: const Key('login_pin'),
                controller: _pinCtrl,
                label: 'PIN',
                obscureText: true,
                keyboardType: TextInputType.number,
                prefixIcon: const Icon(Icons.lock_outline),
                onSubmitted: (_) => _login(),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              AppPrimaryButton(
                key: const Key('login_submit'),
                label: 'Přihlásit',
                loading: _loading,
                onPressed: _login,
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                'Seed: worker1 / 1234',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
