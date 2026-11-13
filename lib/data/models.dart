import '../util/money.dart';

class Profile {
  final String id;
  final String fullName;
  final String role; // 'owner' | 'manager'
  final bool canPaySalaries;

  const Profile({
    required this.id,
    required this.fullName,
    required this.role,
    required this.canPaySalaries,
  });

  bool get isOwner => role == 'owner';
  bool get mayPaySalaries => isOwner || canPaySalaries;
  String get roleLabel => isOwner ? 'Propriétaire' : 'Gérante';

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        fullName: (m['full_name'] ?? '') as String,
        role: (m['role'] ?? 'manager') as String,
        canPaySalaries: (m['can_pay_salaries'] ?? false) as bool,
      );
}

class SalonSettings {
  final String salonName;
  final String address;
  final String phone;
  final double loyaltyDiscountPct;
  final int pointsPer100Da;
  final String receiptFooter;

  const SalonSettings({
    required this.salonName,
    required this.address,
    required this.phone,
    required this.loyaltyDiscountPct,
    required this.pointsPer100Da,
    required this.receiptFooter,
  });

  factory SalonSettings.fromMap(Map<String, dynamic> m) => SalonSettings(
        salonName: (m['salon_name'] ?? '') as String,
        address: (m['address'] ?? '') as String,
        phone: (m['phone'] ?? '') as String,
        loyaltyDiscountPct: asDouble(m['loyalty_discount_pct']),
        pointsPer100Da: asInt(m['points_per_100_da']),
        receiptFooter: (m['receipt_footer'] ?? '') as String,
      );
}

class Service {
  final String id;
  final String name;
  final String category;
  final int durationMin;
  final int priceCents;
  final bool active;
  final int sortOrder;

  const Service({
    required this.id,
    required this.name,
    required this.category,
    required this.durationMin,
    required this.priceCents,
    required this.active,
    required this.sortOrder,
  });

  String get durationLabel {
    if (durationMin < 60) return '$durationMin min';
    final h = durationMin ~/ 60;
    final m = durationMin % 60;
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
  }

  factory Service.fromMap(Map<String, dynamic> m) => Service(
        id: m['id'] as String,
        name: m['name'] as String,
        category: (m['category'] ?? '') as String,
        durationMin: asInt(m['duration_min']),
        priceCents: asInt(m['price_cents']),
        active: (m['active'] ?? true) as bool,
        sortOrder: asInt(m['sort_order']),
      );
}

enum StockStatus { ok, low, out }

/// Unités de contenance : la base est en ml, g ou pièces.
const contentUnits = <String, String>{'ml': 'ml', 'g': 'g', 'pièce': 'pièce(s)'};

String _plural(String word, double n) {
  if (n < 2 || word.isEmpty || word.endsWith('s') || word.endsWith('x') || word.endsWith('z')) return word;
  if (word.endsWith('au') || word.endsWith('eu')) return '${word}x'; // rouleau -> rouleaux
  return '${word}s';
}

/// 1000 ml -> "1 L", 250 ml -> "250 ml", 1500 g -> "1,5 kg", 100 pièce -> "100 pièces"
String formatContent(double amount, String unit) {
  if (unit == 'ml' && amount >= 1000) return '${formatQty(amount / 1000)} L';
  if (unit == 'g' && amount >= 1000) return '${formatQty(amount / 1000)} kg';
  if (unit == 'pièce') return '${formatQty(amount)} ${_plural('pièce', amount)}';
  return '${formatQty(amount)} $unit';
}

class Product {
  final String id;
  final String name;
  final String category;

  /// Conditionnement : flacon, tube, pot, boîte…
  final String unit;

  /// Stock en conditionnements, avec décimales (2,35 flacons).
  final double quantity;
  final double minQuantity;
  final int costCents;
  final int? salePriceCents;
  final bool active;

  /// Contenance d'un conditionnement, en [contentUnit] (ml, g ou pièce).
  final double contentAmount;
  final String contentUnit;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.quantity,
    required this.minQuantity,
    required this.costCents,
    required this.salePriceCents,
    required this.active,
    required this.contentAmount,
    required this.contentUnit,
  });

  bool get forSale => salePriceCents != null;

  /// true si le produit a une contenance (ex. flacon de 1 L) et pas juste "1 pièce".
  bool get hasContent => !(contentUnit == 'pièce' && contentAmount == 1);

  String get contentLabel => formatContent(contentAmount, contentUnit);

  /// Ex. "Flacon de 1 L"
  String get packagingLabel {
    final u = unit.isEmpty ? 'Unité' : unit[0].toUpperCase() + unit.substring(1);
    return hasContent ? '$u de $contentLabel' : u;
  }

  StockStatus get status {
    if (quantity <= 0.0005) return StockStatus.out;
    if (quantity < minQuantity) return StockStatus.low;
    return StockStatus.ok;
  }

  /// Quantité suggérée pour revenir à deux fois le seuil (conditionnements entiers).
  double get suggestedOrder {
    final missing = minQuantity * 2 - quantity;
    return missing > 0 ? missing.ceilToDouble() : 0;
  }

  int get stockValueCents => quantity > 0 ? (quantity * costCents).round() : 0;

  /// Conditionnements pleins + reste du conditionnement entamé.
  ({int full, double rest}) get split {
    final q = quantity < 0 ? 0.0 : quantity;
    var full = q.floor();
    var rest = (q - full) * contentAmount;
    if (contentAmount - rest < 0.5) {
      full += 1;
      rest = 0.0;
    }
    return (full: full, rest: rest < 0.5 ? 0.0 : rest.roundToDouble());
  }

  /// Ex. "2 flacons + 350 ml", "4 tubes", "0 flacon"
  String get stockLabel {
    if (quantity < 0) return '${formatQty(quantity)} ${_plural(unit, 2)} (à recompter)';
    if (!hasContent) return '${formatQty(quantity)} ${_plural(unit, quantity)}';
    final s = split;
    final base = '${s.full} ${_plural(unit, s.full.toDouble())}';
    if (s.rest == 0) return base;
    return '$base + ${formatContent(s.rest, contentUnit)}';
  }

  factory Product.fromMap(Map<String, dynamic> m) => Product(
        id: m['id'] as String,
        name: m['name'] as String,
        category: (m['category'] ?? '') as String,
        unit: (m['unit'] ?? '') as String,
        quantity: asDouble(m['quantity']),
        minQuantity: asDouble(m['min_quantity']),
        costCents: asInt(m['cost_cents']),
        salePriceCents: m['sale_price_cents'] == null ? null : asInt(m['sale_price_cents']),
        active: (m['active'] ?? true) as bool,
        contentAmount: m['content_amount'] == null ? 1 : asDouble(m['content_amount']),
        contentUnit: (m['content_unit'] ?? 'pièce') as String,
      );
}

class Employee {
  final String id;
  final String fullName;
  final int baseSalaryCents;
  final double commissionPct;
  final bool active;

  const Employee({
    required this.id,
    required this.fullName,
    required this.baseSalaryCents,
    required this.commissionPct,
    required this.active,
  });

  factory Employee.fromMap(Map<String, dynamic> m) => Employee(
        id: m['id'] as String,
        fullName: m['full_name'] as String,
        baseSalaryCents: asInt(m['base_salary_cents']),
        commissionPct: asDouble(m['commission_pct']),
        active: (m['active'] ?? true) as bool,
      );
}

class Customer {
  final String id;
  final String fullName;
  final String phone;
  final bool isLoyal;
  final int loyaltyPoints;

  /// Ce que la cliente doit encore au salon.
  final int creditCents;

  const Customer({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.isLoyal,
    required this.loyaltyPoints,
    required this.creditCents,
  });

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
        id: m['id'] as String,
        fullName: m['full_name'] as String,
        phone: (m['phone'] ?? '') as String,
        isLoyal: (m['is_loyal'] ?? false) as bool,
        loyaltyPoints: asInt(m['loyalty_points']),
        creditCents: asInt(m['credit_cents']),
      );
}

/// Ligne de l'historique du crédit d'une cliente.
class CreditMovement {
  final DateTime at;
  final int deltaCents; // + elle doit plus, - elle a remboursé
  final String kind; // sale_credit | sale_settlement | repayment
  final String? paymentMethod;
  final String note;

  const CreditMovement({
    required this.at,
    required this.deltaCents,
    required this.kind,
    required this.paymentMethod,
    required this.note,
  });

  String get kindLabel => switch (kind) {
        'sale_credit' => 'Reste dû sur un ticket',
        'sale_settlement' => 'Réglé avec un ticket',
        'repayment' => 'Remboursement',
        _ => kind,
      };

  factory CreditMovement.fromMap(Map<String, dynamic> m) => CreditMovement(
        at: DateTime.parse(m['created_at'] as String).toLocal(),
        deltaCents: asInt(m['delta_cents']),
        kind: m['kind'] as String,
        paymentMethod: m['payment_method'] as String?,
        note: (m['note'] ?? '') as String,
      );
}

const expenseCategories = <String, String>{
  'electricite': 'Électricité',
  'eau': 'Eau',
  'loyer': 'Loyer',
  'fournisseurs': 'Fournisseurs',
  'entretien': 'Entretien',
  'autre': 'Autre',
};

const expenseMethods = <String, String>{
  'cash': 'Espèces (caisse)',
  'transfer': 'Virement',
  'cheque': 'Chèque',
};

const saleMethods = <String, String>{
  'cash': 'Espèces',
  'cib': 'Carte CIB',
  'edahabia': 'Edahabia',
};

class Expense {
  final String id;
  final String category;
  final int amountCents;
  final DateTime date;
  final String paymentMethod;
  final String note;
  final String? receiptPath;

  const Expense({
    required this.id,
    required this.category,
    required this.amountCents,
    required this.date,
    required this.paymentMethod,
    required this.note,
    required this.receiptPath,
  });

  String get categoryLabel => expenseCategories[category] ?? category;

  factory Expense.fromMap(Map<String, dynamic> m) => Expense(
        id: m['id'] as String,
        category: m['category'] as String,
        amountCents: asInt(m['amount_cents']),
        date: DateTime.parse(m['expense_date'] as String),
        paymentMethod: (m['payment_method'] ?? 'cash') as String,
        note: (m['note'] ?? '') as String,
        receiptPath: m['receipt_path'] as String?,
      );
}

class PayrollLine {
  final String employeeId;
  final String fullName;
  final int baseCents;
  final int servicesCents;
  final double commissionPct;
  final int commissionCents;
  final bool paid;
  final int? paidTotalCents;

  const PayrollLine({
    required this.employeeId,
    required this.fullName,
    required this.baseCents,
    required this.servicesCents,
    required this.commissionPct,
    required this.commissionCents,
    required this.paid,
    required this.paidTotalCents,
  });

  int get dueCents => baseCents + commissionCents;

  factory PayrollLine.fromMap(Map<String, dynamic> m) => PayrollLine(
        employeeId: m['employee_id'] as String,
        fullName: m['full_name'] as String,
        baseCents: asInt(m['base_cents']),
        servicesCents: asInt(m['services_cents']),
        commissionPct: asDouble(m['commission_pct']),
        commissionCents: asInt(m['commission_cents']),
        paid: (m['paid'] ?? false) as bool,
        paidTotalCents:
            m['paid_total_cents'] == null ? null : asInt(m['paid_total_cents']),
      );
}

class MonthSummary {
  final int revenueCents; // chiffre d'affaires (valeur des tickets)
  final int tickets;
  final int receivedCents; // argent réellement encaissé
  final int expensesCents;
  final int salariesCents;
  final int netCents;
  final int creditOutstandingCents; // crédits clientes en cours

  const MonthSummary({
    required this.revenueCents,
    required this.tickets,
    required this.receivedCents,
    required this.expensesCents,
    required this.salariesCents,
    required this.netCents,
    required this.creditOutstandingCents,
  });

  factory MonthSummary.fromMap(Map<String, dynamic> m) => MonthSummary(
        revenueCents: asInt(m['revenue_cents']),
        tickets: asInt(m['tickets']),
        receivedCents: asInt(m['received_cents']),
        expensesCents: asInt(m['expenses_cents']),
        salariesCents: asInt(m['salaries_cents']),
        netCents: asInt(m['net_cents']),
        creditOutstandingCents: asInt(m['credit_outstanding_cents']),
      );
}

class CashDay {
  final int openingCents;
  final int salesCashCents;
  final int expensesCashCents;
  final int salariesCashCents;
  final int expectedCents;
  final bool closed;
  final int? countedCents;

  const CashDay({
    required this.openingCents,
    required this.salesCashCents,
    required this.expensesCashCents,
    required this.salariesCashCents,
    required this.expectedCents,
    required this.closed,
    required this.countedCents,
  });

  factory CashDay.fromMap(Map<String, dynamic> m) => CashDay(
        openingCents: asInt(m['opening_cents']),
        salesCashCents: asInt(m['sales_cash_cents']),
        expensesCashCents: asInt(m['expenses_cash_cents']),
        salariesCashCents: asInt(m['salaries_cash_cents']),
        expectedCents: asInt(m['expected_cents']),
        closed: (m['closed'] ?? false) as bool,
        countedCents:
            m['counted_cents'] == null ? null : asInt(m['counted_cents']),
      );
}

class LedgerEntry {
  final DateTime at;
  final String kind; // sale | expense | salary
  final String label;
  final int inCents;
  final int outCents;
  final String paymentMethod;

  const LedgerEntry({
    required this.at,
    required this.kind,
    required this.label,
    required this.inCents,
    required this.outCents,
    required this.paymentMethod,
  });

  factory LedgerEntry.fromMap(Map<String, dynamic> m) => LedgerEntry(
        at: DateTime.parse(m['at'] as String).toLocal(),
        kind: m['kind'] as String,
        label: m['label'] as String,
        inCents: asInt(m['in_cents']),
        outCents: asInt(m['out_cents']),
        paymentMethod: (m['payment_method'] ?? '') as String,
      );
}

/// Ligne du ticket en cours (avant encaissement).
class CartLine {
  final String kind; // service | product
  final String refId;
  final String label;
  final int unitPriceCents;
  int quantity;
  final String? employeeId;
  final String? employeeName;

  CartLine({
    required this.kind,
    required this.refId,
    required this.label,
    required this.unitPriceCents,
    this.quantity = 1,
    this.employeeId,
    this.employeeName,
  });

  int get totalCents => unitPriceCents * quantity;

  Map<String, dynamic> toRpc() => {
        'kind': kind,
        if (kind == 'service') 'service_id': refId,
        if (kind == 'product') 'product_id': refId,
        if (employeeId != null) 'employee_id': employeeId,
        'quantity': quantity,
      };
}
