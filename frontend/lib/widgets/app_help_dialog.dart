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

  Widget _section(String key, String title, String body) => ExpansionTile(
        key: Key(key),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        title: Text(title),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(body),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nápověda'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ucpávky'),
              const SizedBox(height: 8),
              Text('Verze $_versionLabel',
                  key: const Key('app_version_label')),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(_message!, key: const Key('app_update_status')),
              ],
              const Divider(height: 24),
              _section(
                'help_section_login',
                'Přihlášení',
                'Přihlaste se svým uživatelským jménem a PINem (6–8 číslic). '
                    'Po přihlášení se data automaticky stáhnou ze serveru, pokud jste online. '
                    'PIN si můžete změnit v Profilu → Změna PINu (zadáte starý a nový PIN). '
                    'Relace zůstává uložená, takže se při dalším spuštění nemusíte přihlašovat znovu.',
              ),
              _section(
                'help_section_jobs',
                'Zakázky a patra',
                'Zakázku otevřete zadáním 8místného čísla zakázky, nebo ji vyberete z uloženého seznamu. '
                    'V zakázce zvolíte patro a uvidíte seznam ucpávek na daném patře. '
                    'Pracovník vidí pouze zakázky, které mu byly přiřazené.',
              ),
              _section(
                'help_section_seal',
                'Založení ucpávky',
                'V seznamu ucpávek na patře klepněte na „Nová ucpávka". Vyplňte:\n'
                    '• číslo ucpávky (předvyplní se návrh),\n'
                    '• systém (Intuseal, Dunamenti, Fischer, Hilti, Protecta) a materiály,\n'
                    '• konstrukci (Beton/Cihla nebo SDK/PUR), umístění (stěna, strop, podlaha, šachta) '
                    'a požární odolnost (60/90/120 min),\n'
                    '• jednotlivé prostupy (EL.V., PVC, VZT, PROSTUP, OCEL) s rozměrem, počtem, izolací a materiály,\n'
                    '• poznámky.\n\n'
                    'Ucpávku uložíte tlačítkem Uložit. Upravovat lze jen ucpávky ve stavu „Rozpracováno".',
              ),
              _section(
                'help_section_photos',
                'Fotky',
                'Ke každé ucpávce je potřeba alespoň jedna fotka. Fotku pořídíte přímo v aplikaci '
                    'nebo vyberete z galerie; fotek může být víc. Fotky se nahrávají na server zvlášť — '
                    'pokud nahrání selže (offline), proběhne automaticky při dalším spojení. '
                    'Nahrané fotky pracovník nemůže mazat.',
              ),
              _section(
                'help_section_drawing',
                'Výkres a značky',
                'Pokud má patro nahraný výkres, otevřete jej tlačítkem výkresu. Ucpávku umístíte tak, '
                    'že vyberete značku a klepnete na místo na výkrese — značka ukazuje číslo ucpávky '
                    'a barvu podle stavu. Polohu lze upravit přetažením. '
                    'Výkres (PNG/JPG) může nahrát pouze vedení/admin.',
              ),
              _section(
                'help_section_status',
                'Stavy a barvy',
                'Barva ucpávky v seznamu i na výkrese ukazuje její stav:\n'
                    '• žlutá — Rozpracováno: pracovník ji ještě upravuje,\n'
                    '• zelená — Zkontrolováno: vedení ji schválilo,\n'
                    '• modrá — Fakturováno: je v procesu fakturace.\n\n'
                    'Po odeslání může stav měnit už jen vedení nebo admin.',
              ),
              _section(
                'help_section_export',
                'Soupisy a export',
                'Soupis sestavíte v sekci Soupisy/Reporty. Vyfiltrujete podle zakázky, pracovníka, data, '
                    'patra, stavu, typu prostupu, materiálu nebo systému, zobrazí se náhled a můžete '
                    'exportovat do PDF nebo CSV. Pracovník vidí v soupisu jen vlastní ucpávky.',
              ),
              _section(
                'help_section_sync',
                'Synchronizace a offline režim',
                'Aplikace funguje i offline — vše uložíte do telefonu a změny se odešlou, jakmile budete online. '
                    'V horní liště se zobrazuje „Offline" a počet čekajících položek. Ručně lze synchronizovat '
                    'v sekci Synchronizace tlačítkem Synchronizovat. Pokud dvě stejná čísla ucpávek vzniknou '
                    'offline, při synchronizaci se zobrazí konflikt — opravte číslo ucpávky a synchronizaci zopakujte.',
              ),
              _section(
                'help_section_update',
                'Aktualizace aplikace',
                'Aktuální verzi vidíte nahoře v tomto okně. Tlačítkem „Zkontrolovat aktualizace" ověříte, '
                    'zda je dostupná novější verze (funkční v Android release aplikaci).',
              ),
            ],
          ),
        ),
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
