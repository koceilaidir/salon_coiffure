import 'package:flutter_test/flutter_test.dart';
import 'package:salon_coiffure/data/models.dart';

Product _p(double qty, {double content = 1000, String unit = 'ml', String pack = 'flacon'}) => Product(
      id: 'x',
      name: 'Shampoing',
      category: 'Soins',
      unit: pack,
      quantity: qty,
      minQuantity: 3,
      costCents: 250000,
      salePriceCents: null,
      active: true,
      contentAmount: content,
      contentUnit: unit,
    );

void main() {
  test('stock avec contenance', () {
    expect(_p(2.35).stockLabel, '2 flacons + 350 ml');
    expect(_p(1).stockLabel, '1 flacon');
    expect(_p(0.94).stockLabel, '0 flacon + 940 ml');
    expect(_p(2.9996).stockLabel, '3 flacons'); // reste < 0,5 ml : arrondi
    expect(_p(0).status, StockStatus.out);
  });

  test('contenance lisible', () {
    expect(_p(1).contentLabel, '1 L');
    expect(_p(1, content: 500).contentLabel, '500 ml');
    expect(_p(1, content: 100, unit: 'pièce', pack: 'boîte').packagingLabel, 'Boîte de 100 pièces');
    expect(_p(4, content: 1, unit: 'pièce', pack: 'rouleau').stockLabel, '4 rouleaux');
  });
}
