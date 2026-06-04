import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/auth/auth_provider.dart';
import 'package:ucpavky/features/auth/profile_screen.dart';

void main() {
  testWidgets('profile screen shows PIN change fields', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith(
            (ref) => {
              'id': 'user-1',
              'username': 'worker1',
              'displayName': 'Worker One',
              'role': 'worker',
              'mustChangePin': false,
            },
          ),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile_pin_current')), findsOneWidget);
    expect(find.byKey(const Key('profile_pin_new')), findsOneWidget);
    expect(find.byKey(const Key('profile_pin_confirm')), findsOneWidget);
    expect(find.byKey(const Key('profile_pin_submit')), findsOneWidget);
  });
}
