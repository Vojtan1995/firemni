import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/features/home/action_items_card.dart';

void main() {
  test('action item routes point to filtered destinations', () {
    expect(actionSearchRoute('returned'), '/search?filters=returned');
    expect(actionSearchRoute('no_photo'), '/search?filters=no_photo');
    expect(actionSearchRoute('status_draft'), '/search?filters=status_draft');
    expect(jobsWithoutActivityRoute, '/jobs-admin?filter=without_activity');
  });
}
