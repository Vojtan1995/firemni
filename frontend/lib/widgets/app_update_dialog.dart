import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_release_info.dart';

Future<void> showAppUpdateDialog({
  required BuildContext context,
  required AppReleaseInfo release,
  required bool forced,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !forced,
    builder: (ctx) => _AppUpdateDialog(release: release, forced: forced),
  );
}

class _AppUpdateDialog extends StatefulWidget {
  const _AppUpdateDialog({required this.release, required this.forced});

  final AppReleaseInfo release;
  final bool forced;

  @override
  State<_AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<_AppUpdateDialog> {
  bool _downloading = false;

  Future<void> _download(String apkUrl) async {
    // Single-shot: zabraň druhému stažení (duplicitní APK ve Staženích).
    if (_downloading) return;
    setState(() => _downloading = true);

    final uri = Uri.parse(apkUrl.trim());
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;

    if (!opened) {
      setState(() => _downloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nepodařilo se otevřít odkaz ke stažení. Zkuste to znovu nebo kontaktujte správce.',
          ),
        ),
      );
      return;
    }

    // U nevynuceného updatu dialog zavři, ať nejde spustit stažení podruhé.
    if (!widget.forced) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    final forced = widget.forced;
    final versionLabel = release.versionName ?? '${release.latestBuild ?? ''}';
    final notes = release.releaseNotes?.trim();
    final apkUrl = release.apkUrl;
    final urlValid = isApkDownloadUrlValid(apkUrl);

    return PopScope(
      canPop: !forced,
      child: AlertDialog(
        title: Text(forced ? 'Vyžadována aktualizace' : 'Nová verze k dispozici'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Verze $versionLabel je k dispozici ke stažení.'),
            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(notes),
            ],
            if (forced) ...[
              const SizedBox(height: 12),
              const Text(
                'Pro pokračování je nutné nainstalovat novou verzi aplikace.',
              ),
            ],
            if (!urlValid) ...[
              const SizedBox(height: 12),
              Text(
                'Odkaz ke stažení není k dispozici. Kontaktujte správce.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          if (!forced)
            TextButton(
              onPressed: _downloading ? null : () => Navigator.pop(context),
              child: const Text('Později'),
            ),
          FilledButton(
            onPressed: (urlValid && !_downloading)
                ? () => _download(apkUrl!)
                : null,
            child: Text(_downloading ? 'Stahuji…' : 'Stáhnout aktualizaci'),
          ),
        ],
      ),
    );
  }
}
