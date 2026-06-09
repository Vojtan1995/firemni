import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/seals/seal_note_helpers.dart';

void main() {
  test('worker payload omits public note', () {
    final payload = <String, dynamic>{'sealNumber': '1'};
    SealNoteHelpers.applyNotesToPayload(
      payload,
      role: 'worker',
      noteText: 'public',
      internalNoteText: 'internal',
    );
    expect(payload.containsKey('note'), isFalse);
    expect(payload['internalNote'], 'internal');
  });

  test('ucetni payload omits internal note', () {
    final payload = <String, dynamic>{'sealNumber': '1'};
    SealNoteHelpers.applyNotesToPayload(
      payload,
      role: 'ucetni',
      noteText: 'public',
      internalNoteText: 'internal',
    );
    expect(payload['note'], 'public');
    expect(payload.containsKey('internalNote'), isFalse);
  });
}
