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

class Product {
  final String id;
  final String name;
  final String category;
  final String unit;
  final double quantity;
  final double minQuantity;
  final int costCents;
  final int? salePriceCents;
  final bool active;

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
  });

  bool get forSale => salePriceCents != null;

  StockStatus get status {
    if (quantity <= 0) return StockStatus.out;
    if (quantity < minQuantity) return StockStatus.low;
    return StockStatus.ok;
  }

  /// Quantité suggérée pour revenir à deux fois le seuil.
  double get suggestedOrder {
    final target = minQuantity * 2;
    final missing = target - quantity;
    return missing > 0 ? missing.ceilToDouble() : 0;
  }

  int get stockValueCents =>
      quantity > 0 ? (quantity * costCents).round() : 0;

  factory Product.fromMap(Map<String, dynamic> m) => Product(
        id: m['id'] as String,
        name: m['name'] as String,
        category: (m['category'] ?? '') as String,
        unit: (m['unit'] ?? '') as String,
        quantity: asDouble(m['quantity']),
        minQuantity: asDouble(m['min_quantity']),
        costCents: asInt(m['cost_cents']),
        salePriceCents:
            m['sale_price_cents'] == null ? null : asInt(m['sale_price_cents']),
        active: (m['active'] ?? true) as bool,
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

  const Customer({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.isLoyal,
    required this.loyaltyPoints,
  });

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
        id: m['id'] as String,
        fullName: m['full_name'] as String,
        phone: (m['phone'] ?? '') as String,
        isLoyal: (m['is_loyal'] ?? false) as bool,
        loyaltyPoints: asInt(m['loyalty_points']),
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
  final int revenueCents;
  final int tickets;
  final int expensesCents;
  final int salariesCents;
  final int netCents;

  const MonthSummary({
    required this.revenueCents,
    required this.tickets,
    required this.expensesCents,
    required this.salariesCents,
    required this.netCents,
  });

  factory MonthSummary.fromMap(Map<String, dynamic> m) => MonthSummary(
        revenueCents: asInt(m['revenue_cents']),
        tickets: asInt(m['tickets']),
        expensesCents: asInt(m['expenses_cents']),
        salariesCents: asInt(m['salaries_cents']),
        netCents: asInt(m['net_cents']),
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
