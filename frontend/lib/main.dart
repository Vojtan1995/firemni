import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router.dart';
import 'core/design_tokens.dart';
import 'core/theme.dart';
import 'features/auth/auth_provider.dart';
import 'features/sync/sync_retry_scheduler.dart';

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
      }
    }
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
    );
  }
}
