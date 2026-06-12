import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_release_info.dart';

Future<void> showAppUpdateDialog({
  required BuildContext context,
  required AppReleaseInfo release,
  required bool forced,
}) {
  final versionLabel = release.versionName ?? '${release.latestBuild ?? ''}';
  final notes = release.releaseNotes?.trim();
  final apkUrl = release.apkUrl;

  return showDialog<void>(
    context: context,
    barrierDismissible: !forced,
    builder: (ctx) => PopScope(
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
            if (!isApkDownloadUrlValid(apkUrl)) ...[
              const SizedBox(height: 12),
              Text(
                'Odkaz ke stažení není k dispozici. Kontaktujte správce.',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          if (!forced)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Později'),
            ),
          FilledButton(
            onPressed: isApkDownloadUrlValid(apkUrl)
                ? () => _openApkDownload(ctx, apkUrl!)
                : null,
            child: const Text('Stáhnout aktualizaci'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _openApkDownload(BuildContext context, String apkUrl) async {
  final uri = Uri.parse(apkUrl.trim());
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!context.mounted) return;
  if (!opened) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Nepodařilo se otevřít odkaz ke stažení. Zkuste to znovu nebo kontaktujte správce.',
        ),
      ),
    );
  }
}
