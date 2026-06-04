import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/core/config.dart';
import 'package:ucpavky/core/router.dart';
import 'package:ucpavky/core/theme.dart';
import 'package:ucpavky/database/database.dart';
import 'package:ucpavky/database/database_provider.dart';
import 'package:ucpavky/features/auth/auth_provider.dart';
import 'package:ucpavky/features/auth/login_screen.dart';
import 'package:ucpavky/features/sync/sync_service.dart';

/// FE-07: widget smoke login → home.
///
/// Strategie:
/// - **UI smoke (bez sítě):** izolovaný [LoginScreen] – ověří pole a tlačítko.
/// - **E2E smoke (síť):** celý router + reálné `POST /api/auth/login` jako
///   [runtime_verification_test.dart] (backend na [AppConfig.apiBaseUrl]).
/// - V testu se přepisuje jen [syncServiceProvider] (no-op sync), aby login
///   nezávisel na sync pull/push; auth zůstává reálné API.
/// - [FlutterSecureStorage.setMockInitialValues] kvůli headless testu.
class _NoopSyncService extends SyncService {
  _NoopSyncService(super.ref);

  @override
  Future<SyncResult> syncAll({bool force = true}) async =>
      SyncResult(success: true);
}

Future<bool> _backendReachable() async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/health');
    final req = await client.getUrl(uri);
    final res = await req.close();
    return res.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close();
  }
}

Widget _smokeApp({List<Override> extraOverrides = const []}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWith((ref) {
        final db = AppDatabase.forTesting();
        ref.onDispose(db.close);
        return db;
      }),
      syncServiceProvider.overrideWith((ref) => _NoopSyncService(ref)),
      ...extraOverrides,
    ],
    child: Consumer(
      builder: (context, ref, _) => MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: ref.watch(routerProvider),
      ),
    ),
  );
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('FE-07 login → home widget smoke', () {
    testWidgets('login screen shows username, PIN and submit', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: const LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ucpávky'), findsOneWidget);
      expect(find.byKey(const Key('login_username')), findsOneWidget);
      expect(find.byKey(const Key('login_pin')), findsOneWidget);
      expect(find.byKey(const Key('login_submit')), findsOneWidget);
    });

    testWidgets('worker1 login navigates to home menu', (tester) async {
      final backendUp = await _backendReachable();
      expect(
        backendUp,
        isTrue,
        reason:
            'Backend must run at ${AppConfig.apiBaseUrl} (same as runtime_verification_test)',
      );

      await tester.pumpWidget(_smokeApp());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_username')), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('login_username')), 'worker1');
      await tester.enterText(find.byKey(const Key('login_pin')), '1234');
      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pump();

      // Do not pumpAndSettle while login shows CircularProgressIndicator (infinite animation).
      var foundHome = false;
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        if (find.text('Hlavní menu').evaluate().isNotEmpty) {
          foundHome = true;
          break;
        }
      }

      if (!foundHome) {
        final visibleTexts = tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .whereType<String>()
            .where((t) => t.isNotEmpty)
            .toList();
        fail(
          'Expected navigation to home after login. Visible texts: $visibleTexts',
        );
      }
      expect(find.text('Stavba'), findsOneWidget);
      expect(find.text('Neplatné přihlašovací údaje'), findsNothing);
    });
    testWidgets('mustChangePin user is routed to PIN change screen',
        (tester) async {
      await tester.pumpWidget(
        _smokeApp(
          extraOverrides: [
            authUserProvider.overrideWith(
              (ref) => {
                'id': 'user-1',
                'username': 'worker1',
                'displayName': 'Worker One',
                'role': 'worker',
                'mustChangePin': true,
              },
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('change_pin_submit')), findsOneWidget);
      expect(find.text('Hlavní menu'), findsNothing);
    });
  });
}
