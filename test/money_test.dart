import 'package:flutter_test/flutter_test.dart';
import 'package:salon_coiffure/util/money.dart';

void main() {
  test('formatDa', () {
    expect(formatDa(150000), '1 500,00 DA');
    expect(formatDa(589000), '5 890,00 DA');
    expect(formatDa(41275000), '412 750,00 DA');
    expect(formatDa(5), '0,05 DA');
    expect(formatDa(-31000), '-310,00 DA');
    expect(formatDa(1432000, suffix: false), '14 320,00');
  });

  test('parseDa', () {
    expect(parseDa('14 320,00'), 1432000);
    expect(parseDa('14320'), 1432000);
    expect(parseDa('14320.5'), 1432050);
    expect(parseDa('0,05'), 5);
    expect(parseDa('1 500,00 DA'), 150000);
    expect(parseDa('abc'), null);
    expect(parseDa('1,234,5'), null);
    expect(parseDa(''), null);
  });

  test('aller-retour saisie', () {
    for (final c in [0, 1, 99, 100, 150000, 123456789]) {
      expect(parseDa(centsToInput(c)), c);
    }
  });

  test('formatQty', () {
    expect(formatQty(4), '4');
    expect(formatQty(3.5), '3,5');
    expect(formatQty(0.25), '0,25');
  });
}
