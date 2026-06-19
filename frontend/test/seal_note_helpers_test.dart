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

  test('vedeni payload sets both note and internal note', () {
    final payload = <String, dynamic>{'sealNumber': '1'};
    SealNoteHelpers.applyNotesToPayload(
      payload,
      role: 'vedeni',
      noteText: 'public',
      internalNoteText: 'internal',
    );
    expect(payload['note'], 'public');
    expect(payload['internalNote'], 'internal');
  });
}
