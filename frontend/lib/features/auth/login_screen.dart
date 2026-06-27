import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
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
  final _mfaCtrl = TextEditingController();
  bool _loading = false;
  bool _mfaMode = false;
  bool _recoveryMode = false;
  String? _challengeToken;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final outcome = await ref
          .read(authServiceProvider)
          .login(_userCtrl.text.trim(), _pinCtrl.text);
      if (outcome.mfaRequired) {
        _challengeToken = outcome.challengeToken;
        if (outcome.enrollmentRequired) {
          await _enrollMfa(outcome.challengeToken!);
        } else {
          setState(() => _mfaMode = true);
        }
        return;
      }
      await _finishLogin();
    } catch (e) {
      setState(() => _error = _apiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _apiError(Object error) {
    if (error is DioException && error.response?.data is Map) {
      final data = error.response!.data as Map;
      return data['error'] as String? ?? 'Přihlášení se nezdařilo';
    }
    return 'Přihlášení se nezdařilo';
  }

  Future<void> _finishLogin() async {
      final mustChangePin =
          ref.read(authUserProvider)?['mustChangePin'] == true;
      if (mustChangePin) {
        if (mounted) context.go('/change-pin');
        return;
      }
      await ref.read(syncServiceProvider).syncAll();
      if (mounted) context.go('/');
  }

  Future<void> _verifyMfa() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_recoveryMode) {
        await ref
            .read(authServiceProvider)
            .useMfaRecovery(_challengeToken!, _mfaCtrl.text.trim());
      } else {
        await ref
            .read(authServiceProvider)
            .verifyMfaLogin(_challengeToken!, _mfaCtrl.text.trim());
      }
      await _finishLogin();
    } catch (e) {
      setState(() => _error = _apiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _enrollMfa(String challengeToken) async {
    final setup =
        await ref.read(authServiceProvider).startMfaEnrollment(challengeToken);
    if (!mounted) return;
    final codeCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Nastavení dvoufázového ověření'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'V Authenticatoru přidejte účet ručně pomocí tohoto klíče:',
              ),
              const SizedBox(height: 12),
              SelectableText(
                setup['secret'] as String,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Šestimístný kód'),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Aktivovat'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final recoveryCodes = await ref
        .read(authServiceProvider)
        .confirmMfaEnrollment(challengeToken, codeCtrl.text.trim());
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Recovery kódy'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Uložte je do firemního trezoru. Znovu se nezobrazí.',
              ),
              const SizedBox(height: 12),
              SelectableText(recoveryCodes.join('\n')),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Mám bezpečně uloženo'),
          ),
        ],
      ),
    );
    await _finishLogin();
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
                _mfaMode
                    ? (_recoveryMode
                        ? 'Zadejte jednorázový recovery kód'
                        : 'Zadejte kód z Authenticatoru')
                    : 'Přihlášení jménem a PINem nebo admin heslem',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xxl),
              if (!_mfaMode) AppTextField(
                key: const Key('login_username'),
                controller: _userCtrl,
                label: 'Uživatelské jméno',
                textInputAction: TextInputAction.next,
                prefixIcon: const Icon(Icons.person_outline),
              ),
              if (!_mfaMode) const SizedBox(height: AppSpacing.lg),
              if (!_mfaMode) AppTextField(
                key: const Key('login_pin'),
                controller: _pinCtrl,
                label: 'PIN / admin heslo',
                obscureText: true,
                prefixIcon: const Icon(Icons.lock_outline),
                onSubmitted: (_) => _login(),
              ),
              if (_mfaMode)
                AppTextField(
                  key: const Key('login_mfa'),
                  controller: _mfaCtrl,
                  label: _recoveryMode ? 'Recovery kód' : 'MFA kód',
                  keyboardType:
                      _recoveryMode ? TextInputType.text : TextInputType.number,
                  prefixIcon: const Icon(Icons.verified_user_outlined),
                  onSubmitted: (_) => _verifyMfa(),
                ),
              if (_mfaMode)
                TextButton(
                  onPressed: () => setState(() {
                    _recoveryMode = !_recoveryMode;
                    _mfaCtrl.clear();
                    _error = null;
                  }),
                  child: Text(
                    _recoveryMode
                        ? 'Použít kód z Authenticatoru'
                        : 'Použít recovery kód',
                  ),
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
                label: _mfaMode ? 'Ověřit' : 'Přihlásit',
                loading: _loading,
                onPressed: _mfaMode ? _verifyMfa : _login,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
