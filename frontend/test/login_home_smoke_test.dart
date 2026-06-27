import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
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
/// - **Router smoke (bez sítě):** celý router + fake auth service, protože
///   `testWidgets` blokuje reálný [HttpClient]. Reálné API ověřuje
///   [runtime_verification_test.dart].
/// - V testu se přepisuje [syncServiceProvider] (no-op sync), aby login
///   nezávisel na sync pull/push.
/// - [FlutterSecureStorage.setMockInitialValues] kvůli headless testu.
class _FakeAuthService extends AuthService {
  _FakeAuthService(this.ref) : super(ref);

  final Ref ref;

  @override
  Future<LoginOutcome> login(String username, String pin) async {
    if (username != 'worker1' || pin != '1234') {
      throw Exception('Invalid credentials');
    }
    ref.read(authTokenProvider.notifier).state = 'test-token';
    ref.read(authUserProvider.notifier).state = {
      'id': 'user-worker1',
      'username': 'worker1',
      'displayName': 'Worker 1',
      'role': 'worker',
      'mustChangePin': false,
    };
    return const LoginOutcome(authenticated: true);
  }
}

class _NoopSyncService extends SyncService {
  _NoopSyncService(super.ref);

  @override
  Future<SyncResult> syncAll({bool force = true}) async =>
      SyncResult(success: true);
}

Widget _smokeApp({
  bool useFakeAuth = false,
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWith((ref) {
        final db = AppDatabase.forTesting();
        ref.onDispose(db.close);
        return db;
      }),
      if (useFakeAuth)
        authServiceProvider.overrideWith((ref) => _FakeAuthService(ref)),
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
      await tester.pumpWidget(_smokeApp(useFakeAuth: true));
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
      expect(find.text('Zakázky'), findsOneWidget);
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
