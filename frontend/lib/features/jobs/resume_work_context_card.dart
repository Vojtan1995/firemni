import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_tokens.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_provider.dart';
import '../sync/sync_service.dart';
import 'work_context_service.dart';

/// Karta „Zpět do stavby“ — home i profil.
class ResumeWorkContextCard extends ConsumerStatefulWidget {
  const ResumeWorkContextCard({super.key});

  @override
  ConsumerState<ResumeWorkContextCard> createState() =>
      _ResumeWorkContextCardState();
}

class _ResumeWorkContextCardState extends ConsumerState<ResumeWorkContextCard> {
  WorkContext? _context;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final ctx = await ref.read(workContextServiceProvider).load(userId);
    if (!mounted) return;
    setState(() => _context = ctx);
  }

  Future<void> _resume() async {
    final ctx = _context;
    if (ctx == null) return;
    try {
      await ref.read(syncServiceProvider).syncAll(force: false);
    } catch (_) {}
    if (!mounted) return;
    final route = ref.read(workContextServiceProvider).resumeRoute(ctx);
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final ctx = _context;
    if (ctx == null || !ctx.hasResumeTarget) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        borderColor: AppColors.accent.withValues(alpha: 0.4),
        leading: const AppIconBox(icon: Icons.construction),
        title: 'Zpět do stavby',
        subtitle: ctx.resumeSubtitle,
        onTap: _resume,
      ),
    );
  }
}
