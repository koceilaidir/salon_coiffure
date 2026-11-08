// Fichier volontairement présent pour que `flutter create .` ne génère pas
// le test d'exemple par défaut (qui ne compile pas avec cette application).
import 'package:flutter_test/flutter_test.dart';
import 'package:salon_coiffure/data/models.dart';

void main() {
  test('CartLine.toRpc', () {
    final l = CartLine(kind: 'service', refId: 'abc', label: 'Brushing', unitPriceCents: 150000, employeeId: 'e1');
    expect(l.toRpc(), {'kind': 'service', 'service_id': 'abc', 'employee_id': 'e1', 'quantity': 1});
    l.quantity = 2;
    expect(l.totalCents, 300000);
  });
}
