import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../printing/receipt_printer.dart';
import '../theme.dart';
import '../util/money.dart';
import '../widgets/common.dart';
import 'settings_screen.dart' show showCustomerDialog;

const _productsTab = 'Produits en vente';

/// Écran 1 : la caisse.
class PosScreen extends StatefulWidget {
  final Profile profile;
  final VoidCallback onDataChanged;
  const PosScreen({super.key, required this.profile, required this.onDataChanged});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  bool _loading = true;
  Object? _error;

  List<Service> _services = [];
  List<Product> _forSale = [];
  List<Employee> _employees = [];
  List<Customer> _customers = [];
  SalonSettings? _settings;
  int _todayCount = 0;

  String _category = '';
  String _search = '';
  final List<CartLine> _cart = [];
  String? _customerId;
  String? _employeeId;
  String _method = 'cash';
  final _paidCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _paidCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait([
        repo.services(),
        repo.products(),
        repo.employees(),
        repo.customers(),
        repo.settings(),
        repo.salesCountOn(DateTime.now()),
      ]);
      if (!mounted) return;
      setState(() {
        _services = r[0] as List<Service>;
        _forSale = (r[1] as List<Product>).where((p) => p.forSale).toList();
        _employees = r[2] as List<Employee>;
        _customers = r[3] as List<Customer>;
        _settings = r[4] as SalonSettings;
        _todayCount = r[5] as int;
        final cats = _categories;
        if (!cats.contains(_category)) _category = cats.isEmpty ? '' : cats.first;
        if (_employeeId != null && !_employees.any((e) => e.id == _employeeId)) _employeeId = null;
        _employeeId ??= _employees.isEmpty ? null : _employees.first.id;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<String> get _categories {
    final cats = <String>[];
    for (final s in _services) {
      if (!cats.contains(s.category)) cats.add(s.category);
    }
    if (_forSale.isNotEmpty) cats.add(_productsTab);
    return cats;
  }

  Customer? get _customer {
    for (final c in _customers) {
      if (c.id == _customerId) return c;
    }
    return null;
  }

  Employee? get _employee {
    for (final e in _employees) {
      if (e.id == _employeeId) return e;
    }
    return null;
  }

  int get _subtotal => _cart.fold(0, (a, l) => a + l.totalCents);

  /// Même calcul que la base (round half away from zero). Le montant
  /// imprimé est toujours celui renvoyé par le serveur.
  int get _discount {
    final c = _customer;
    final s = _settings;
    if (c == null || !c.isLoyal || s == null || s.loyaltyDiscountPct <= 0) return 0;
    return (_subtotal * s.loyaltyDiscountPct / 100).round();
  }

  int get _total => _subtotal - _discount;

  int? get _paidCents => _paidCtrl.text.trim().isEmpty ? null : parseDa(_paidCtrl.text);

  void _addService(Service s) {
    final emp = _employee;
    setState(() {
      _cart.add(CartLine(
        kind: 'service',
        refId: s.id,
        label: s.name,
        unitPriceCents: s.priceCents,
        employeeId: emp?.id,
        employeeName: emp?.fullName,
      ));
    });
  }

  void _addProduct(Product p) {
    final emp = _employee;
    setState(() {
      for (final l in _cart) {
        if (l.kind == 'product' && l.refId == p.id) {
          l.quantity++;
          return;
        }
      }
      _cart.add(CartLine(
        kind: 'product',
        refId: p.id,
        label: p.name,
        unitPriceCents: p.salePriceCents ?? 0,
        employeeId: emp?.id,
        employeeName: emp?.fullName,
      ));
    });
  }

  void _clear() {
    setState(() {
      _cart.clear();
      _customerId = null;
      _method = 'cash';
      _paidCtrl.clear();
    });
  }

  Future<void> _newCustomer() async {
    final c = await showCustomerDialog(context);
    if (c == null || !mounted) return;
    setState(() {
      _customers = [..._customers, c]..sort((a, b) => a.fullName.compareTo(b.fullName));
      _customerId = c.id;
    });
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    final paid = _paidCents;
    if (_method == 'cash' && _paidCtrl.text.trim().isNotEmpty) {
      if (paid == null) {
        showError(context, Exception('Montant reçu invalide.'));
        return;
      }
      if (paid < _total) {
        showError(context, Exception('Le montant reçu est inférieur au total.'));
        return;
      }
    }
    setState(() => _busy = true);
    final lines = List<CartLine>.from(_cart);
    try {
      final sale = await repo.createSale(
        lines: lines,
        paymentMethod: _method,
        paidCents: _method == 'cash' ? paid : null,
        customerId: _customerId,
      );
      final customer = _customerId == null ? null : await repo.customer(_customerId!);
      if (!mounted) return;
      _clear();
      widget.onDataChanged();
      final ticket = sale['ticket_no'];
      try {
        await ReceiptPrinter.printSale(
          settings: _settings!,
          sale: sale,
          lines: lines,
          cashierName: widget.profile.fullName,
          customer: customer,
        );
        if (mounted) showInfo(context, 'Ticket n° $ticket encaissé et imprimé.');
      } catch (e) {
        if (mounted) {
          showError(context, Exception('Ticket n° $ticket encaissé, mais le reçu n\'a pas pu être imprimé : ${errorMessage(e)}'));
        }
      }
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _settings == null || _error != null) {
      return LoadState(error: _error, onRetry: _load);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _catalog()),
          const SizedBox(width: 24),
          SizedBox(width: 400, child: _ticket()),
        ],
      ),
    );
  }

  // ------------------------- Catalogue -------------------------
  Widget _catalog() {
    final q = _search.toLowerCase();
    final List<Widget> tiles;
    if (q.isNotEmpty) {
      tiles = [
        for (final s in _services.where((s) => s.name.toLowerCase().contains(q))) _serviceTile(s),
        for (final p in _forSale.where((p) => p.name.toLowerCase().contains(q))) _productTile(p),
      ];
    } else if (_category == _productsTab) {
      tiles = [for (final p in _forSale) _productTile(p)];
    } else {
      tiles = [for (final s in _services.where((s) => s.category == _category)) _serviceTile(s)];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenHeader(
          title: 'Caisse',
          subtitle: '${dayLabel(DateTime.now())} · $_todayCount encaissement${_todayCount > 1 ? 's' : ''} aujourd\'hui',
          actions: [
            SizedBox(
              width: 300,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Rechercher une prestation ou un produit',
                ),
                onChanged: (v) => setState(() => _search = v.trim()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in _categories)
            ChoicePill(
              label: c,
              selected: _search.isEmpty && c == _category,
              onTap: () => setState(() => _category = c),
            ),
        ]),
        const SizedBox(height: 18),
        Expanded(
          child: tiles.isEmpty
              ? Center(
                  child: Text(
                    _services.isEmpty
                        ? 'Aucune prestation. Ajoutez-les dans Réglages > Prestations.'
                        : 'Aucun résultat.',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                )
              : GridView.extent(
                  maxCrossAxisExtent: 240,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.9,
                  children: tiles,
                ),
        ),
      ],
    );
  }

  Widget _tile({required String title, required String left, required String price, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              Row(children: [
                Expanded(child: Text(left, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
                Text(price, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serviceTile(Service s) =>
      _tile(title: s.name, left: s.durationLabel, price: formatDa(s.priceCents), onTap: () => _addService(s));

  Widget _productTile(Product p) => _tile(
        title: p.name,
        left: 'Stock : ${formatQty(p.quantity)}',
        price: formatDa(p.salePriceCents ?? 0),
        onTap: () => _addProduct(p),
      );

  // ------------------------- Ticket -------------------------
  Widget _ticket() {
    final customer = _customer;
    final change = (_method == 'cash' && _paidCents != null) ? _paidCents! - _total : 0;
    return Panel(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Expanded(child: SectionTitle('Ticket en cours')),
            TextButton(onPressed: _cart.isEmpty ? null : _clear, child: const Text('Vider')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use
                value: _customerId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cliente'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Cliente de passage')),
                  for (final c in _customers)
                    DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(c.isLoyal ? '${c.fullName} (fidèle)' : c.fullName, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _customerId = v),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(
              tooltip: 'Nouvelle cliente',
              onPressed: _newCustomer,
              icon: const Icon(Icons.person_add_alt),
            ),
          ]),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            // ignore: deprecated_member_use
            value: _employeeId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Coiffeuse (pour les prochaines lignes)'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Aucune')),
              for (final e in _employees) DropdownMenuItem<String?>(value: e.id, child: Text(e.fullName)),
            ],
            onChanged: (v) => setState(() => _employeeId = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _cart.isEmpty
                ? const Center(
                    child: Text('Touchez une prestation pour l\'ajouter',
                        style: TextStyle(color: AppColors.muted)),
                  )
                : ListView.separated(
                    itemCount: _cart.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final l = _cart[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(l.quantity > 1 ? '${l.quantity} × ${l.label}' : l.label),
                              if (l.employeeName != null)
                                Text(l.employeeName!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                            ]),
                          ),
                          Text(formatDa(l.totalCents), style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            tooltip: 'Retirer la ligne',
                            iconSize: 18,
                            onPressed: () => setState(() => _cart.removeAt(i)),
                            icon: const Icon(Icons.close),
                          ),
                        ]),
                      );
                    },
                  ),
          ),
          const Divider(),
          KeyValueRow('Sous-total', formatDa(_subtotal)),
          if (_discount > 0) KeyValueRow('Remise fidélité', '-${formatDa(_discount)}'),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            const Expanded(child: Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            Text(formatDa(_total), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
          ]),
          if (customer != null && customer.isLoyal && (_settings?.loyaltyDiscountPct ?? 0) == 0)
            const Text('Cliente fidèle : aucune remise réglée (Réglages > Salon).',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 12),
          const Text('Paiement', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 6),
          Row(children: [
            for (final e in saleMethods.entries) ...[
              Expanded(
                child: ChoicePill(
                  label: e.value,
                  selected: _method == e.key,
                  dark: false,
                  onTap: () => setState(() => _method = e.key),
                ),
              ),
              if (e.key != saleMethods.keys.last) const SizedBox(width: 8),
            ],
          ]),
          if (_method == 'cash') ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _paidCtrl,
                  decoration: const InputDecoration(labelText: 'Montant reçu (facultatif)', suffixText: 'DA'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 130,
                child: Text(
                  change > 0 ? 'Rendu\n${formatDa(change)}' : '',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            onPressed: _cart.isEmpty || _busy ? null : _checkout,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.print_outlined),
            label: const Text('Encaisser et imprimer le reçu'),
          ),
        ],
      ),
    );
  }
}
