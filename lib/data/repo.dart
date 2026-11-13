import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime monthStart(DateTime d) => DateTime(d.year, d.month);
DateTime nextMonth(DateTime d) => DateTime(d.year, d.month + 1);

/// Toutes les lectures/écritures Supabase de l'application.
class Repo {
  SupabaseClient get db => Supabase.instance.client;

  // ---------------- Compte ----------------
  Future<Profile?> myProfile() async {
    final uid = db.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await db.from('profiles').select().eq('id', uid).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  Future<void> signIn(String email, String password) =>
      db.auth.signInWithPassword(email: email, password: password);

  Future<void> signOut() => db.auth.signOut();

  // ---------------- Réglages ----------------
  Future<SalonSettings> settings() async {
    final row = await db.from('salon_settings').select().eq('id', 1).single();
    return SalonSettings.fromMap(row);
  }

  Future<void> updateSettings(Map<String, dynamic> values) =>
      db.from('salon_settings').update(values).eq('id', 1);

  // ---------------- Prestations ----------------
  Future<List<Service>> services({bool includeInactive = false}) async {
    var q = db.from('services').select();
    if (!includeInactive) q = q.eq('active', true);
    final rows = await q.order('category').order('sort_order').order('name');
    return rows.map(Service.fromMap).toList();
  }

  Future<String> saveService(String? id, Map<String, dynamic> values) async {
    if (id == null) {
      final row = await db.from('services').insert(values).select('id').single();
      return row['id'] as String;
    }
    await db.from('services').update(values).eq('id', id);
    return id;
  }

  /// Produits consommés par une prestation : {productId: quantité}
  Future<Map<String, double>> serviceConsumption(String serviceId) async {
    final rows = await db
        .from('service_products')
        .select('product_id, quantity')
        .eq('service_id', serviceId);
    return {
      for (final r in rows)
        r['product_id'] as String: (r['quantity'] as num).toDouble(),
    };
  }

  Future<void> setServiceConsumption(
      String serviceId, Map<String, double> items) async {
    await db.from('service_products').delete().eq('service_id', serviceId);
    if (items.isEmpty) return;
    await db.from('service_products').insert([
      for (final e in items.entries)
        {'service_id': serviceId, 'product_id': e.key, 'quantity': e.value},
    ]);
  }

  // ---------------- Stock ----------------
  Future<List<Product>> products({bool includeInactive = false}) async {
    var q = db.from('products').select();
    if (!includeInactive) q = q.eq('active', true);
    final rows = await q.order('category').order('name');
    return rows.map(Product.fromMap).toList();
  }

  Future<int> lowStockCount() async {
    final list = await products();
    return list.where((p) => p.status != StockStatus.ok).length;
  }

  /// Création : `values` peut contenir la quantité initiale.
  Future<void> createProduct(Map<String, dynamic> values) =>
      db.from('products').insert(values);

  /// Modification : la quantité n'est jamais modifiée ici (voir stockEntry).
  Future<void> updateProduct(String id, Map<String, dynamic> values) {
    final v = Map<String, dynamic>.from(values)..remove('quantity');
    return db.from('products').update(v).eq('id', id);
  }

  Future<void> stockEntry(String productId, double delta,
          {String reason = 'restock', String note = ''}) =>
      db.rpc('stock_entry', params: {
        'p_product_id': productId,
        'p_delta': delta,
        'p_reason': reason,
        'p_note': note,
      });

  // ---------------- Employées ----------------
  Future<List<Employee>> employees({bool includeInactive = false}) async {
    var q = db.from('employees').select();
    if (!includeInactive) q = q.eq('active', true);
    final rows = await q.order('full_name');
    return rows.map(Employee.fromMap).toList();
  }

  Future<void> saveEmployee(String? id, Map<String, dynamic> values) async {
    if (id == null) {
      await db.from('employees').insert(values);
    } else {
      await db.from('employees').update(values).eq('id', id);
    }
  }

  // ---------------- Clientes ----------------
  Future<List<Customer>> customers() async {
    final rows = await db.from('customers').select().order('full_name');
    return rows.map(Customer.fromMap).toList();
  }

  Future<Customer> saveCustomer(String? id, Map<String, dynamic> values) async {
    final Map<String, dynamic> row;
    if (id == null) {
      row = await db.from('customers').insert(values).select().single();
    } else {
      row = await db.from('customers').update(values).eq('id', id).select().single();
    }
    return Customer.fromMap(row);
  }

  Future<Customer?> customer(String id) async {
    final row = await db.from('customers').select().eq('id', id).maybeSingle();
    return row == null ? null : Customer.fromMap(row);
  }

  // ---------------- Ventes ----------------
  /// Enregistre la vente côté serveur (prix, remise et stock calculés par la base).
  Future<Map<String, dynamic>> createSale({
    required List<CartLine> lines,
    required String paymentMethod,
    int? paidCents,
    String? customerId,
    bool settleDebt = true,
  }) async {
    final res = await db.rpc('create_sale', params: {
      'p_items': lines.map((l) => l.toRpc()).toList(),
      'p_payment_method': paymentMethod,
      'p_paid_cents': paidCents,
      'p_customer_id': customerId,
      'p_settle_debt': settleDebt,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// La cliente rembourse tout ou partie de son crédit (sans prestation).
  Future<Customer> repayCredit({
    required String customerId,
    required int amountCents,
    required String paymentMethod,
    String note = '',
  }) async {
    final res = await db.rpc('repay_credit', params: {
      'p_customer_id': customerId,
      'p_amount_cents': amountCents,
      'p_payment_method': paymentMethod,
      'p_note': note,
    });
    return Customer.fromMap(Map<String, dynamic>.from(res as Map));
  }

  Future<List<CreditMovement>> creditHistory(String customerId) async {
    final rows = await db
        .from('customer_credit_movements')
        .select()
        .eq('customer_id', customerId)
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(CreditMovement.fromMap).toList();
  }

  Future<int> salesCountOn(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final rows = await db
        .from('sales')
        .select('id')
        .isFilter('cancelled_at', null)
        .gte('created_at', start.toUtc().toIso8601String())
        .lt('created_at', end.toUtc().toIso8601String());
    return rows.length;
  }

  // ---------------- Dépenses ----------------
  Future<List<Expense>> expenses(DateTime month) async {
    final rows = await db
        .from('expenses')
        .select()
        .gte('expense_date', _day(monthStart(month)))
        .lt('expense_date', _day(nextMonth(month)))
        .order('expense_date', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(Expense.fromMap).toList();
  }

  Future<void> addExpense({
    required String category,
    required int amountCents,
    required DateTime date,
    required String paymentMethod,
    required String note,
    String? localReceiptPath,
  }) async {
    String? storedPath;
    if (localReceiptPath != null) {
      final file = File(localReceiptPath);
      final ext = localReceiptPath.split('.').last.toLowerCase();
      storedPath =
          '${date.year}/${date.month.toString().padLeft(2, '0')}/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await db.storage.from('expense-receipts').upload(storedPath, file);
    }
    await db.from('expenses').insert({
      'category': category,
      'amount_cents': amountCents,
      'expense_date': _day(date),
      'payment_method': paymentMethod,
      'note': note,
      'receipt_path': storedPath,
    });
  }

  Future<void> attachReceipt(Expense e, String localPath) async {
    final ext = localPath.split('.').last.toLowerCase();
    final path =
        '${e.date.year}/${e.date.month.toString().padLeft(2, '0')}/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await db.storage.from('expense-receipts').upload(path, File(localPath));
    await db.from('expenses').update({'receipt_path': path}).eq('id', e.id);
  }

  Future<String> receiptUrl(String path) =>
      db.storage.from('expense-receipts').createSignedUrl(path, 600);

  // ---------------- Compta & paie ----------------
  Future<MonthSummary> monthSummary(DateTime month) async {
    final res = await db.rpc('month_summary', params: {'p_month': _day(monthStart(month))});
    return MonthSummary.fromMap(Map<String, dynamic>.from((res as List).first as Map));
  }

  Future<List<PayrollLine>> payroll(DateTime month) async {
    final res = await db.rpc('payroll_month', params: {'p_month': _day(monthStart(month))});
    return (res as List)
        .map((r) => PayrollLine.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> payEmployee({
    required String employeeId,
    required DateTime month,
    int bonusCents = 0,
    String method = 'cash',
  }) async {
    final res = await db.rpc('pay_employee', params: {
      'p_employee_id': employeeId,
      'p_month': _day(monthStart(month)),
      'p_bonus_cents': bonusCents,
      'p_method': method,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<LedgerEntry>> ledger(DateTime month) async {
    final start = monthStart(month);
    final end = nextMonth(month);
    final rows = await db
        .from('ledger')
        .select()
        .gte('at', start.toUtc().toIso8601String())
        .lt('at', end.toUtc().toIso8601String())
        .order('at');
    return rows.map(LedgerEntry.fromMap).toList();
  }

  Future<CashDay> cashDay(DateTime day) async {
    final res = await db.rpc('cash_day', params: {'p_date': _day(day)});
    return CashDay.fromMap(Map<String, dynamic>.from((res as List).first as Map));
  }

  Future<Map<String, dynamic>> closeDay(DateTime day, int countedCents, String note) async {
    final res = await db.rpc('close_day', params: {
      'p_date': _day(day),
      'p_counted_cents': countedCents,
      'p_note': note,
    });
    return Map<String, dynamic>.from(res as Map);
  }
}

final repo = Repo();
