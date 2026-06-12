import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router.dart';
import 'core/design_tokens.dart';
import 'core/desktop_esc_handler.dart';
import 'core/theme.dart';
import 'core/api/api_client.dart';
import 'core/app_update_service.dart';
import 'features/auth/auth_provider.dart';
import 'features/sync/sync_retry_scheduler.dart';
import 'widgets/app_update_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: UcpavkyApp()));
}

class UcpavkyApp extends ConsumerStatefulWidget {
  const UcpavkyApp({super.key});

  @override
  ConsumerState<UcpavkyApp> createState() => _UcpavkyAppState();
}

class _UcpavkyAppState extends ConsumerState<UcpavkyApp> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await ref.read(authServiceProvider).tryRestoreSession();
    } catch (_) {
      // Session restore failed — show login.
    } finally {
      if (mounted) {
        setState(() => _ready = true);
        ref.read(syncRetrySchedulerProvider).start();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkAppUpdate();
        });
      }
    }
  }

  Future<void> _checkAppUpdate() async {
    final result = await evaluateAppUpdate(ref.read(dioProvider));
    if (!mounted || result == null) return;
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null || !navContext.mounted) return;
    await showAppUpdateDialog(
      context: navContext,
      release: result.release,
      forced: result.forced,
    );
  }

  @override
  void dispose() {
    ref.read(syncRetrySchedulerProvider).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          ),
        ),
      );
    }
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Ucpávky',
      theme: AppTheme.dark,
      routerConfig: router,
      builder: (context, child) =>
          DesktopEscScope(child: child ?? const SizedBox.shrink()),
    );
  }
}
