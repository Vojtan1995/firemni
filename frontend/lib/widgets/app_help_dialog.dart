import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/app_update_service.dart';
import '../core/design_tokens.dart';
import 'app_update_dialog.dart';

typedef PackageInfoLoader = Future<PackageInfo> Function();
typedef ManualUpdateChecker = Future<ManualAppUpdateCheckResult> Function();

Future<void> showAppHelpDialog({
  required BuildContext context,
  required Dio dio,
  required String? userRole,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => AppHelpDialog(
      dio: dio,
      userRole: userRole,
    ),
  );
}

class AppHelpDialog extends StatefulWidget {
  const AppHelpDialog({
    super.key,
    required this.dio,
    required this.userRole,
    this.packageInfoLoader,
    this.updateChecker,
  });

  final Dio dio;
  final String? userRole;
  final PackageInfoLoader? packageInfoLoader;
  final ManualUpdateChecker? updateChecker;

  @override
  State<AppHelpDialog> createState() => _AppHelpDialogState();
}

class _HelpSection {
  const _HelpSection({
    required this.key,
    required this.title,
    required this.icon,
    required this.body,
    required this.roles,
  });

  final String key;
  final String title;
  final IconData icon;
  final String body;
  final Set<String> roles;

  bool isVisibleFor(String? role) {
    if (role == null) return roles.contains('worker');
    return roles.contains(role);
  }
}

class _AppHelpDialogState extends State<AppHelpDialog> {
  String _versionLabel = 'Načítání...';
  bool _checking = false;
  String? _message;
  ManualAppUpdateStatus? _messageStatus;

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
    final navigator = Navigator.of(context);
    final navigatorContext = navigator.context;

    setState(() {
      _checking = true;
      _message = null;
      _messageStatus = null;
    });

    final result = await (widget.updateChecker ??
        () => checkAppUpdateManually(widget.dio))();
    if (!mounted) return;

    if (result.status == ManualAppUpdateStatus.updateAvailable) {
      final update = result.update!;
      navigator.pop();
      if (!navigatorContext.mounted) return;
      await showAppUpdateDialog(
        context: navigatorContext,
        release: update.release,
        forced: update.forced,
      );
      return;
    }

    setState(() {
      _checking = false;
      _messageStatus = result.status;
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

  String get _roleLabel => switch (widget.userRole) {
        'worker' => 'pracovníka',
        'vedeni' => 'vedení',
        'admin' => 'admina',
        _ => 'pracovníka',
      };

  List<_HelpSection> get _sections => const [
        _HelpSection(
          key: 'help_section_login',
          title: 'Přihlášení a PIN',
          icon: Icons.login,
          roles: {'worker', 'vedeni', 'admin'},
          body: 'Přihlaste se svým uživatelským jménem a PINem '
              '(6-8 číslic).\n\n'
              'Po přihlášení se data automaticky stáhnou ze serveru, pokud '
              'jste online.\n\n'
              'PIN si můžete změnit v Profilu -> Změna PINu. Zadáte starý PIN '
              'a nový PIN.\n\n'
              'Relace zůstává uložená, takže se při dalším spuštění nemusíte '
              'přihlašovat znovu.',
        ),
        _HelpSection(
          key: 'help_section_jobs',
          title: 'Zakázky a patra',
          icon: Icons.work_outline,
          roles: {'worker', 'vedeni', 'admin'},
          body: 'Zakázku otevřete zadáním 8místného čísla zakázky, nebo ji '
              'vyberete z uloženého seznamu.\n\n'
              'V zakázce zvolíte patro a uvidíte seznam ucpávek na daném '
              'patře.\n\n'
              'Pracovník vidí pouze zakázky, které mu byly přiřazené.',
        ),
        _HelpSection(
          key: 'help_section_seal',
          title: 'Založení ucpávky',
          icon: Icons.add_circle_outline,
          roles: {'worker', 'vedeni', 'admin'},
          body: 'V seznamu ucpávek na patře klepněte na "Nová ucpávka". '
              'Vyplňte:\n\n'
              '- číslo ucpávky, návrh se předvyplní,\n'
              '- systém a materiály,\n'
              '- konstrukci, umístění a požární odolnost,\n'
              '- jednotlivé prostupy s rozměrem, počtem, izolací a materiály,\n'
              '- poznámky.\n\n'
              'Ucpávku uložíte tlačítkem Uložit. Upravovat lze jen ucpávky ve '
              'stavu Rozpracováno.',
        ),
        _HelpSection(
          key: 'help_section_photos',
          title: 'Fotky',
          icon: Icons.photo_camera_outlined,
          roles: {'worker', 'vedeni', 'admin'},
          body: 'Ke každé ucpávce je potřeba alespoň jedna fotka.\n\n'
              'Fotku pořídíte přímo v aplikaci nebo vyberete z galerie. Fotek '
              'může být víc.\n\n'
              'Fotky se nahrávají na server zvlášť. Pokud nahrání selže '
              'offline, proběhne automaticky při dalším spojení.\n\n'
              'Nahrané fotky pracovník nemůže mazat.',
        ),
        _HelpSection(
          key: 'help_section_drawing',
          title: 'Výkres a značky',
          icon: Icons.map_outlined,
          roles: {'worker', 'vedeni', 'admin'},
          body: 'Pokud má patro nahraný výkres, otevřete jej tlačítkem '
              'výkresu.\n\n'
              'Ucpávku umístíte tak, že vyberete značku a klepnete na místo '
              'na výkrese.\n\n'
              'Značka ukazuje číslo ucpávky a barvu podle stavu. Polohu lze '
              'upravit přetažením.',
        ),
        _HelpSection(
          key: 'help_section_status',
          title: 'Stavy a barvy',
          icon: Icons.palette_outlined,
          roles: {'worker', 'vedeni', 'admin'},
          body: 'Barva ucpávky v seznamu i na výkrese ukazuje její stav:\n\n'
              '- Rozpracováno: ucpávku lze ještě upravovat,\n'
              '- Ke kontrole: ucpávka čeká na kontrolu,\n'
              '- Zkontrolováno: ucpávka prošla kontrolou,\n'
              '- Fakturováno: ucpávka je uzavřená pro fakturaci.\n\n'
              'Po odeslání už běžně neupravujete stav ucpávky.',
        ),
        _HelpSection(
          key: 'help_section_worker_reports',
          title: 'Moje soupisy',
          icon: Icons.description_outlined,
          roles: {'worker'},
          body: 'V sekci Moje soupisy uvidíte soupisy práce, které se týkají '
              'vašich ucpávek.\n\n'
              'Můžete otevřít uložené soupisy, zkontrolovat položky a pracovat '
              'jen s daty, která patří k vašim zakázkám.',
        ),
        _HelpSection(
          key: 'help_section_management_reports',
          title: 'Soupisy, kontrola a fakturace',
          icon: Icons.fact_check_outlined,
          roles: {'vedeni', 'admin'},
          body: 'V sekci Soupisy práce filtrujete podle zakázky, pracovníka, '
              'data, patra, stavu, typu prostupu, materiálu nebo systému.\n\n'
              'Z náhledu lze exportovat PDF nebo CSV. Vedení a admin řeší '
              'kontrolu, připravení k fakturaci a uzavření fakturovaných '
              'položek.',
        ),
        _HelpSection(
          key: 'help_section_management_jobs',
          title: 'Správa staveb a výkresů',
          icon: Icons.admin_panel_settings_outlined,
          roles: {'vedeni', 'admin'},
          body: 'Ve správě staveb zakládáte a upravujete zakázky, patra a '
              'přiřazení pracovníků.\n\n'
              'Výkres patra nahrajete jako PNG nebo JPG. Po nahrání ho mohou '
              'pracovníci používat pro umístění značek ucpávek.',
        ),
        _HelpSection(
          key: 'help_section_management_users_logs',
          title: 'Uživatelé a logy',
          icon: Icons.manage_accounts_outlined,
          roles: {'vedeni', 'admin'},
          body:
              'V sekci Uživatelé spravujete účty, role a aktivitu uživatelů.\n\n'
              'Logy slouží ke kontrole důležitých událostí v aplikaci, '
              'přihlášení, synchronizace a změn v datech.',
        ),
        _HelpSection(
          key: 'help_section_admin_trash',
          title: 'Koš a obnova',
          icon: Icons.delete_outline,
          roles: {'admin'},
          body: 'Koš je dostupný jen pro admina. Slouží ke kontrole smazaných '
              'položek a případné obnově, pokud je to potřeba.',
        ),
        _HelpSection(
          key: 'help_section_sync',
          title: 'Synchronizace a offline režim',
          icon: Icons.sync_outlined,
          roles: {'worker', 'vedeni', 'admin'},
          body: 'Aplikace funguje i offline. Změny se uloží do zařízení a '
              'odešlou se, jakmile budete online.\n\n'
              'V horní liště se zobrazuje Offline a počet čekajících položek.\n\n'
              'Ručně lze synchronizovat v sekci Synchronizace tlačítkem '
              'Synchronizovat.\n\n'
              'Pokud dvě stejná čísla ucpávek vzniknou offline, při '
              'synchronizaci se zobrazí konflikt. Opravte číslo ucpávky a '
              'synchronizaci zopakujte.',
        ),
        _HelpSection(
          key: 'help_section_update',
          title: 'Aktualizace aplikace',
          icon: Icons.system_update,
          roles: {'worker', 'vedeni', 'admin'},
          body: 'Aktuální verzi vidíte nahoře v tomto okně.\n\n'
              'Tlačítkem "Zkontrolovat aktualizace" ověříte, zda je dostupná '
              'novější verze.\n\n'
              'Ruční kontrola je funkční v Android release aplikaci.',
        ),
      ];

  Color _statusColor() {
    return switch (_messageStatus) {
      ManualAppUpdateStatus.upToDate => AppColors.success,
      ManualAppUpdateStatus.unavailable => AppColors.error,
      ManualAppUpdateStatus.unsupported => AppColors.warning,
      _ => AppColors.info,
    };
  }

  IconData _statusIcon() {
    return switch (_messageStatus) {
      ManualAppUpdateStatus.upToDate => Icons.check_circle_outline,
      ManualAppUpdateStatus.unavailable => Icons.wifi_off_outlined,
      ManualAppUpdateStatus.unsupported => Icons.info_outline,
      _ => Icons.info_outline,
    };
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: AppRadius.smAll,
                ),
                child: const Icon(
                  Icons.help_outline,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ucpávky',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Detailní nápověda pro $_roleLabel',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            key: const Key('app_version_label'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.smAll,
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'Verze $_versionLabel',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _updateStatus(BuildContext context) {
    final message = _message;
    if (message == null) return const SizedBox.shrink();

    final color = _statusColor();
    return Container(
      key: const Key('app_update_status'),
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.smAll,
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_statusIcon(), color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, _HelpSection section) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.bgSecondary,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: const BorderSide(color: AppColors.border),
        ),
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: Key(section.key),
            tilePadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadius.smAll,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(
                section.icon,
                size: 20,
                color: AppColors.textPrimary,
              ),
            ),
            title: Text(
              section.title,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            iconColor: AppColors.textPrimary,
            collapsedIconColor: AppColors.textSecondary,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  section.body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleSections =
        _sections.where((section) => section.isVisibleFor(widget.userRole));
    final width = MediaQuery.sizeOf(context).width;

    return AlertDialog(
      title: const Text('Nápověda'),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      content: SizedBox(
        width: width < 640 ? double.maxFinite : 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context),
              _updateStatus(context),
              const SizedBox(height: AppSpacing.lg),
              ...visibleSections.map((section) => _section(context, section)),
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
