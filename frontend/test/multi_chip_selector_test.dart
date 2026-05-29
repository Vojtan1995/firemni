import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/seals/multi_chip_selector.dart';

void main() {
  testWidgets('MultiChipSelector toggles multiple options', (tester) async {
    var selected = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return MultiChipSelector(
                label: 'Materiály',
                options: const ['FiAM', 'FiGM', 'Jiný'],
                selected: selected,
                onChanged: (next) => setState(() => selected = next),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('FiAM'));
    await tester.pumpAndSettle();
    expect(selected, ['FiAM']);

    await tester.tap(find.text('FiGM'));
    await tester.pumpAndSettle();
    expect(selected, ['FiAM', 'FiGM']);

    await tester.tap(find.text('FiAM'));
    await tester.pumpAndSettle();
    expect(selected, ['FiGM']);
  });

  testWidgets('MultiChipSelector adds custom value', (tester) async {
    var selected = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return MultiChipSelector(
                label: 'Materiály',
                options: const ['A', 'B'],
                selected: selected,
                allowCustom: true,
                onChanged: (next) => setState(() => selected = next),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Vlastní'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'CustomMat');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(selected, ['CustomMat']);
    expect(find.text('CustomMat'), findsOneWidget);
  });
}
