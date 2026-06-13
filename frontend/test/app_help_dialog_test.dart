import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ucpavky/core/app_release_info.dart';
import 'package:ucpavky/core/app_update_service.dart';
import 'package:ucpavky/widgets/app_help_dialog.dart';

void main() {
  PackageInfo packageInfo() => PackageInfo(
        appName: 'Ucpávky',
        packageName: 'cz.unifast.ucpavky',
        version: '1.2.3',
        buildNumber: '7',
      );

  Future<void> pumpHelpDialog(
    WidgetTester tester,
    ManualUpdateChecker checker,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppHelpDialog(
            dio: Dio(),
            packageInfoLoader: () async => packageInfo(),
            updateChecker: checker,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows real app version', (tester) async {
    await pumpHelpDialog(
      tester,
      () async => const ManualAppUpdateCheckResult(
        status: ManualAppUpdateStatus.upToDate,
      ),
    );

    expect(find.text('Verze 1.2.3 (7)'), findsOneWidget);
  });

  testWidgets('shows latest version status', (tester) async {
    await pumpHelpDialog(
      tester,
      () async => const ManualAppUpdateCheckResult(
        status: ManualAppUpdateStatus.upToDate,
      ),
    );

    await tester.tap(find.byKey(const Key('check_app_update')));
    await tester.pumpAndSettle();

    expect(find.text('Používáte nejnovější verzi.'), findsOneWidget);
  });

  testWidgets('shows connection error', (tester) async {
    await pumpHelpDialog(
      tester,
      () async => const ManualAppUpdateCheckResult(
        status: ManualAppUpdateStatus.unavailable,
      ),
    );

    await tester.tap(find.byKey(const Key('check_app_update')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Kontrola aktualizací se nezdařila. Zkontrolujte připojení a zkuste to znovu.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('disables update button while checking', (tester) async {
    final completer = Completer<ManualAppUpdateCheckResult>();
    await pumpHelpDialog(tester, () => completer.future);

    await tester.tap(find.byKey(const Key('check_app_update')));
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('check_app_update')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Kontroluji...'), findsOneWidget);

    completer.complete(
      const ManualAppUpdateCheckResult(
        status: ManualAppUpdateStatus.upToDate,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('shows unsupported platform status', (tester) async {
    await pumpHelpDialog(
      tester,
      () async => const ManualAppUpdateCheckResult(
        status: ManualAppUpdateStatus.unsupported,
      ),
    );

    await tester.tap(find.byKey(const Key('check_app_update')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Ruční kontrola aktualizací je dostupná pouze v Android release aplikaci.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('opens download dialog for newer build', (tester) async {
    await pumpHelpDialog(
      tester,
      () async => const ManualAppUpdateCheckResult(
        status: ManualAppUpdateStatus.updateAvailable,
        update: AppUpdateCheckResult(
          release: AppReleaseInfo(
            platform: 'android',
            updateAvailable: true,
            versionName: '2.0.0',
            latestBuild: 8,
            minBuild: 7,
            apkUrl: 'https://releases.example.com/app.apk',
          ),
          currentBuild: 7,
          forced: false,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('check_app_update')));
    await tester.pumpAndSettle();

    expect(find.text('Nová verze k dispozici'), findsOneWidget);
    expect(find.text('Stáhnout aktualizaci'), findsOneWidget);
  });
}
