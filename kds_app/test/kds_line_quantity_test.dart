import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/board/kds_line_quantity.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';

void main() {
  group('KdsLineQuantity.forQueue', () {
    test('prep uses server quantity as display amount', () {
      expect(
        KdsLineQuantity.forQueue({
          'quantity': 3,
          'line_quantity': 5,
          'prep_quantity': 2,
        }, BoardQueue.pendingPrep),
        3,
      );
    });

    test('prep prefers prep_remaining', () {
      expect(
        KdsLineQuantity.forQueue({
          'prep_remaining': 4,
          'quantity': 99,
        }, BoardQueue.pendingPrep),
        4,
      );
    });

    test('cook prefers cook_remaining', () {
      expect(
        KdsLineQuantity.forQueue({
          'cook_remaining': 2,
          'quantity': 8,
        }, BoardQueue.pendingCook),
        2,
      );
    });

    test('ready_serve uses remaining_quantity', () {
      expect(
        KdsLineQuantity.forQueue({
          'remaining_quantity': 3,
          'quantity': 5,
        }, BoardQueue.readyServe),
        3,
      );
    });
  });

  group('KdsLineQuantity.forGroup', () {
    test('prefers group quantity for prep', () {
      expect(
        KdsLineQuantity.forGroup(
          {'quantity': 5, 'remaining_quantity': 0},
          [
            {'quantity': 1, 'remaining_quantity': 0},
          ],
          BoardQueue.pendingPrep,
        ),
        5,
      );
    });

    test('ready_serve prefers remaining_quantity', () {
      expect(
        KdsLineQuantity.forGroup(
          {'quantity': 5, 'remaining_quantity': 3},
          [
            {'quantity': 5, 'remaining_quantity': 3},
          ],
          BoardQueue.readyServe,
        ),
        3,
      );
    });
  });
}
