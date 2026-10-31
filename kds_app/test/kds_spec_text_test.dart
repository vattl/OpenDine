import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/board/kds_spec_text.dart';

void main() {
  group('KdsSpecText', () {
    test('uses readable group spec_norm', () {
      expect(KdsSpecText.display(specNorm: '大份'), '大份');
    });

    test('parses selectedSpicy json into comma-separated values without titles',
        () {
      expect(
        KdsSpecText.display(
          lines: [
            {'selectedSpicy': '{"辣度":"不辣","成熟度":"9成熟","温度":"常温"}'},
          ],
          includeTaste: true,
        ),
        '不辣,9成熟,常温',
      );
    });

    test('parses mixed spec and taste dimensions with comma join', () {
      expect(
        KdsSpecText.display(
          lines: [
            {'selectedSpicy': '{"份量":"大份","辣度":"微辣"}'},
          ],
          includeTaste: true,
        ),
        '大份,微辣',
      );
    });

    test('prefers line selectedSpicy over internal spec_norm hash', () {
      expect(
        KdsSpecText.display(
          specNorm: 'a1b2c3d4e5f6789012345678901234',
          lines: [
            {'selectedSpicy': '{"份量":"大份"}'},
          ],
        ),
        '大份',
      );
    });

    test('resolveGroupSpec from lines', () {
      expect(
        KdsSpecText.resolveGroupSpec(
          const {},
          [
            {'selectedSpicy': '{"份量":"半份"}'},
          ],
        ),
        '半份',
      );
    });

    test('resolveGroupTaste from lines', () {
      expect(
        KdsSpecText.resolveGroupTaste(
          const {},
          [
            {'selectedSpicy': '{"辣度":"特辣"}'},
          ],
        ),
        '特辣',
      );
    });

    test(
        'does not duplicate when line has selectedSpicy and group spec_norm/taste_norm',
        () {
      expect(
        KdsSpecText.display(
          specNorm: '9成熟',
          tasteNorm: '不辣',
          lines: [
            {'selectedSpicy': '{"辣度":"不辣","成熟度":"9成熟","温度":"常温"}'},
          ],
          includeTaste: true,
        ),
        '不辣,9成熟,常温',
      );
    });

    test('ignores empty normalized values', () {
      expect(KdsSpecText.display(specNorm: '-'), isNull);
      expect(KdsSpecText.display(specNorm: 'default'), isNull);
    });
  });
}
