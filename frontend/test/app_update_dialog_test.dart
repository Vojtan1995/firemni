import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/core/app_release_info.dart';
import 'package:ucpavky/widgets/app_update_dialog.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required bool forced,
    String? apkUrl,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showAppUpdateDialog(
                  context: context,
                  release: AppReleaseInfo(
                    platform: 'android',
                    updateAvailable: true,
                    versionName: '1.1.0',
                    latestBuild: 2,
                    minBuild: 1,
                    apkUrl: apkUrl,
                    releaseNotes: 'Opravy a vylepšení',
                  ),
                  forced: forced,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('optional update shows Pozdeji and enabled download', (tester) async {
    await pumpDialog(
      tester,
      forced: false,
      apkUrl: 'https://releases.example.com/app.apk',
    );

    expect(find.text('Nová verze k dispozici'), findsOneWidget);
    expect(find.text('Později'), findsOneWidget);
    expect(find.text('Stáhnout aktualizaci'), findsOneWidget);
    expect(find.text('Opravy a vylepšení'), findsOneWidget);
  });

  testWidgets('forced update hides Pozdeji', (tester) async {
    await pumpDialog(
      tester,
      forced: true,
      apkUrl: 'https://releases.example.com/app.apk',
    );

    expect(find.text('Vyžadována aktualizace'), findsOneWidget);
    expect(find.text('Později'), findsNothing);
    expect(
      find.text('Pro pokračování je nutné nainstalovat novou verzi aplikace.'),
      findsOneWidget,
    );
  });

  testWidgets('invalid APK URL shows error and disables download', (tester) async {
    await pumpDialog(tester, forced: false, apkUrl: 'http://insecure/app.apk');

    expect(
      find.text('Odkaz ke stažení není k dispozici. Kontaktujte správce.'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
