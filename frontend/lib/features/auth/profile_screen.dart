import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';
import '../jobs/resume_work_context_card.dart';
import '../sync/sync_service.dart';
import 'auth_provider.dart';
import 'profile_worksheets_section.dart';

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
    if (newPin.length < 6 || newPin.length > 8) {
      setState(() {
        _error = 'Nový PIN musí mít 6 až 8 číslic';
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
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const ResumeWorkContextCard(),
            AppCard(
              showChevron: false,
              leading: AppIconBox(
                icon: Icons.person,
                backgroundColor: AppColors.bgSecondary,
                color: AppColors.textPrimary,
              ),
              title: user['displayName'] as String? ?? '',
              subtitle: '${user['username']} · $role',
            ),
            const SizedBox(height: AppSpacing.xl),
            ProfileWorksheetsSection(role: role),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(title: 'Změna PINu', style: SectionHeaderStyle.h3),
            Text(
              'Zadejte starý PIN, nový PIN a jeho potvrzení.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              key: const Key('profile_pin_current'),
              controller: _currentCtrl,
              label: 'Aktuální PIN',
              obscureText: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              prefixIcon: const Icon(Icons.lock_outline),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              key: const Key('profile_pin_new'),
              controller: _newCtrl,
              label: 'Nový PIN',
              obscureText: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              prefixIcon: const Icon(Icons.lock_reset),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              key: const Key('profile_pin_confirm'),
              controller: _confirmCtrl,
              label: 'Potvrdit nový PIN',
              obscureText: true,
              keyboardType: TextInputType.number,
              prefixIcon: const Icon(Icons.check_circle_outline),
              onSubmitted: (_) => _changePin(),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
            if (_success != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_success!, style: const TextStyle(color: AppColors.success)),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(
              key: const Key('profile_pin_submit'),
              label: 'Uložit nový PIN',
              loading: _loading,
              onPressed: _changePin,
            ),
          ],
        ),
      ),
    );
  }
}
