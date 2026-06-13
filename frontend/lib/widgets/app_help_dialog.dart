import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/app_update_service.dart';
import 'app_update_dialog.dart';

typedef PackageInfoLoader = Future<PackageInfo> Function();
typedef ManualUpdateChecker = Future<ManualAppUpdateCheckResult> Function();

Future<void> showAppHelpDialog({
  required BuildContext context,
  required Dio dio,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => AppHelpDialog(dio: dio),
  );
}

class AppHelpDialog extends StatefulWidget {
  const AppHelpDialog({
    super.key,
    required this.dio,
    this.packageInfoLoader,
    this.updateChecker,
  });

  final Dio dio;
  final PackageInfoLoader? packageInfoLoader;
  final ManualUpdateChecker? updateChecker;

  @override
  State<AppHelpDialog> createState() => _AppHelpDialogState();
}

class _AppHelpDialogState extends State<AppHelpDialog> {
  String _versionLabel = 'Načítání...';
  bool _checking = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info =
          await (widget.packageInfoLoader ?? PackageInfo.fromPlatform)();
      if (!mounted) return;
      setState(() => _versionLabel = '${info.version} (${info.buildNumber})');
    } catch (_) {
      if (mounted) setState(() => _versionLabel = 'Neznámá');
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _message = null;
    });

    final result = await (widget.updateChecker ??
        () => checkAppUpdateManually(widget.dio))();
    if (!mounted) return;

    if (result.status == ManualAppUpdateStatus.updateAvailable) {
      final update = result.update!;
      final navigator = Navigator.of(context);
      final navigatorContext = navigator.context;
      navigator.pop();
      await showAppUpdateDialog(
        context: navigatorContext,
        release: update.release,
        forced: update.forced,
      );
      return;
    }

    setState(() {
      _checking = false;
      _message = switch (result.status) {
        ManualAppUpdateStatus.upToDate => 'Používáte nejnovější verzi.',
        ManualAppUpdateStatus.unavailable =>
          'Kontrola aktualizací se nezdařila. Zkontrolujte připojení a zkuste to znovu.',
        ManualAppUpdateStatus.unsupported =>
          'Ruční kontrola aktualizací je dostupná pouze v Android release aplikaci.',
        ManualAppUpdateStatus.updateAvailable => null,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nápověda'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ucpávky'),
          const SizedBox(height: 8),
          Text('Verze $_versionLabel', key: const Key('app_version_label')),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!, key: const Key('app_update_status')),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(),
          child: const Text('Zavřít'),
        ),
        FilledButton.icon(
          key: const Key('check_app_update'),
          onPressed: _checking ? null : _checkForUpdates,
          icon: _checking
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update),
          label: Text(
            _checking ? 'Kontroluji...' : 'Zkontrolovat aktualizace',
          ),
        ),
      ],
    );
  }
}
