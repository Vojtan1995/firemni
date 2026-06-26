import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'api/api_client.dart';
import 'router.dart';
import '../features/auth/auth_provider.dart';

/// Globální zachytávač chyb: když u uživatele nastane pád/error, nabídne mu
/// chybu nahlásit. Hlášení jde na /api/client-errors a vedení ho vidí v Logách.
class ErrorReporter {
  ErrorReporter._(this._container);

  static ErrorReporter? _instance;
  static ErrorReporter get instance => _instance!;

  static void init(ProviderContainer container) {
    _instance = ErrorReporter._(container);
  }

  final ProviderContainer _container;
  bool _dialogVisible = false;
  DateTime? _lastShown;
  String? _appVersion;

  Future<String> _version() async {
    if (_appVersion != null) return _appVersion!;
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _appVersion = 'unknown';
    }
    return _appVersion!;
  }

  /// Zachytí chybu a (pokud je uživatel přihlášen) nabídne ji nahlásit.
  void capture(Object error, StackTrace? stack) {
    // Hlásit může jen přihlášený uživatel (endpoint vyžaduje auth).
    if (_container.read(authUserProvider) == null) return;

    // Debounce: ne víc než 1 dialog za 5 s a ne když už je nějaký zobrazený,
    // aby smyčka chyb nezahltila UI.
    final now = DateTime.now();
    if (_dialogVisible) return;
    if (_lastShown != null &&
        now.difference(_lastShown!) < const Duration(seconds: 5)) {
      return;
    }
    _lastShown = now;

    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    _showDialog(ctx, error, stack);
  }

  Future<void> _showDialog(
    BuildContext context,
    Object error,
    StackTrace? stack,
  ) async {
    _dialogVisible = true;
    // Route zachytíme ještě před asynchronním dialogem.
    String? route;
    try {
      route = GoRouterState.of(context).uri.toString();
    } catch (_) {
      // Mimo router – route prostě neuvedeme.
    }
    try {
      final report = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Nastala chyba'),
          content: const Text(
            'V aplikaci došlo k chybě. Můžete ji nahlásit, '
            'aby ji vývojáři mohli opravit.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Zavřít'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Nahlásit'),
            ),
          ],
        ),
      );
      if (report == true) {
        final ok = await _send(error, stack, route);
        final messenger = context.mounted
            ? ScaffoldMessenger.maybeOf(context)
            : null;
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              ok ? 'Chyba nahlášena. Děkujeme.' : 'Nahlášení se nezdařilo.',
            ),
          ),
        );
      }
    } finally {
      _dialogVisible = false;
    }
  }

  Future<bool> _send(
    Object error,
    StackTrace? stack,
    String? route,
  ) async {
    try {
      await _container.read(dioProvider).post('/api/client-errors', data: {
        'message': error.toString(),
        if (stack != null) 'stack': stack.toString(),
        if (route != null) 'route': route,
        'appVersion': await _version(),
        'platform': defaultTargetPlatform.name,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
