import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../hardware/hardware.dart';
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
  bool _settleDebt = true;
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
        if (_customerId != null && !_customers.any((c) => c.id == _customerId)) _customerId = null;
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

  // ------------------------- Montants -------------------------
  int get _subtotal => _cart.fold(0, (a, l) => a + l.totalCents);

  /// Même calcul que la base. Le montant imprimé est toujours celui du serveur.
  int get _discount {
    final c = _customer;
    final s = _settings;
    if (c == null || !c.isLoyal || s == null || s.loyaltyDiscountPct <= 0) return 0;
    return (_subtotal * s.loyaltyDiscountPct / 100).round();
  }

  int get _total => _subtotal - _discount;

  /// Ancien crédit de la cliente ajouté à ce ticket.
  int get _debtIncluded {
    final c = _customer;
    if (c == null || !_settleDebt || c.creditCents <= 0) return 0;
    return c.creditCents;
  }

  int get _due => _total + _debtIncluded;

  /// Montant reçu saisi (null = champ vide = montant exact).
  int? get _paidInput => _paidCtrl.text.trim().isEmpty ? null : parseDa(_paidCtrl.text);
  bool get _paidInvalid => _paidCtrl.text.trim().isNotEmpty && _paidInput == null;
  int get _received => _paidInput ?? _due;
  int get _change => _method == 'cash' && _received > _due ? _received - _due : 0;
  int get _remaining => _received < _due ? _due - _received : 0;

  void _setPaid(int cents) {
    _paidCtrl.text = centsToInput(cents);
    setState(() {});
  }

  void _addToPaid(int cents) => _setPaid((_paidInput ?? 0) + cents);

  // ------------------------- Ticket -------------------------
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
      _settleDebt = true;
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

  Future<void> _openDrawer() async {
    try {
      await Hardware.openDrawer();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    if (_paidInvalid) {
      showError(context, Exception('Montant reçu invalide. Exemple : 2 000 ou 1 500,50'));
      return;
    }
    final customer = _customer;
    if (_method != 'cash' && _received > _due) {
      showError(context, Exception('Un paiement par carte ne peut pas dépasser le montant à payer.'));
      return;
    }
    if (_remaining > 0) {
      if (customer == null) {
        showError(context, Exception('Pour laisser un reste à payer, choisissez d\'abord la cliente.'));
        return;
      }
      final ok = await confirm(
        context,
        'Laisser un crédit ?',
        '${customer.fullName} paie ${formatDa(_received)} sur ${formatDa(_due)}.\n'
            'Il restera ${formatDa(_remaining)} à payer. Ce montant sera ajouté à son prochain ticket.',
        ok: 'Oui, laisser en crédit',
      );
      if (!ok) return;
    }

    setState(() => _busy = true);
    final lines = List<CartLine>.from(_cart);
    final method = _method;
    try {
      final sale = await repo.createSale(
        lines: lines,
        paymentMethod: method,
        paidCents: _paidInput,
        customerId: _customerId,
        settleDebt: _settleDebt,
      );
      final freshCustomer = _customerId == null ? null : await repo.customer(_customerId!);
      if (!mounted) return;
      _clear();
      widget.onDataChanged();
      final ticket = sale['ticket_no'];

      if (method == 'cash' && Hardware.drawerEnabled && Hardware.drawerAutoOnCash) {
        try {
          await Hardware.openDrawer();
        } catch (_) {
          // Le tiroir peut s'ouvrir à la main ; on ne bloque pas l'encaissement.
        }
      }
      try {
        await ReceiptPrinter.printSale(
          settings: _settings!,
          sale: sale,
          lines: lines,
          cashierName: widget.profile.fullName,
          customer: freshCustomer,
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

  // ------------------------- Mise en page -------------------------
  @override
  Widget build(BuildContext context) {
    if (_loading && _settings == null || _error != null) {
      return LoadState(error: _error, onRetry: _load);
    }
    return LayoutBuilder(builder: (context, c) {
      final pad = screenPadding(c.maxWidth);
      final wide = c.maxWidth >= 980;
      if (wide) {
        final ticketWidth = (c.maxWidth * 0.36).clamp(360.0, 440.0);
        return Padding(
          padding: pad,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _catalog(c.maxWidth)),
              const SizedBox(width: 24),
              SizedBox(width: ticketWidth, child: _ticketPanel()),
            ],
          ),
        );
      }
      // Écran étroit : catalogue en haut, ticket en dessous (la page défile).
      return SingleChildScrollView(
        padding: pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 460, child: _catalog(c.maxWidth)),
            const SizedBox(height: 16),
            _ticketPanel(scrollable: false),
          ],
        ),
      );
    });
  }

  // ------------------------- Catalogue -------------------------
  Widget _catalog(double width) {
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
            if (Hardware.drawerEnabled)
              OutlinedButton.icon(
                onPressed: _openDrawer,
                icon: const Icon(Icons.inbox_outlined),
                label: const Text('Ouvrir le tiroir'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher…',
              ),
              onChanged: (v) => setState(() => _search = v.trim()),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        // Catégories sur une seule ligne (défilement horizontal si elles ne tiennent pas)
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final c = _categories[i];
              return Center(
                child: ChoicePill(
                  label: c,
                  selected: _search.isEmpty && c == _category,
                  onTap: () => setState(() => _category = c),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
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
                  maxCrossAxisExtent: width < 700 ? 200 : 240,
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
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              Row(children: [
                Expanded(
                  child: Text(left,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                ),
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
  /// [scrollable] : en mode large, le panneau a une hauteur fixe ; si l'écran est
  /// trop bas, tout le ticket défile au lieu de déborder.
  Widget _ticketPanel({bool scrollable = true}) {
    return Panel(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(builder: (context, c) {
        final fixedHeight = scrollable && c.maxHeight.isFinite && c.maxHeight >= 700;
        final top = _ticketTop();
        final bottom = _ticketBottom();
        if (fixedHeight) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ...top,
            Expanded(child: _cartList(shrink: false)),
            ...bottom,
          ]);
        }
        final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ...top,
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 80, maxHeight: 260),
            child: _cartList(shrink: true),
          ),
          ...bottom,
        ]);
        return c.maxHeight.isFinite ? SingleChildScrollView(child: content) : content;
      }),
    );
  }

  List<Widget> _ticketTop() {
    final customer = _customer;
    return [
      Row(children: [
        const Expanded(child: SectionTitle('Ticket en cours')),
        TextButton(onPressed: _cart.isEmpty && _customerId == null ? null : _clear, child: const Text('Vider')),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: AppDropdown<String?>(
            value: _customerId,
            label: 'Cliente',
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Cliente de passage')),
              for (final c in _customers)
                DropdownMenuItem<String?>(
                  value: c.id,
                  child: Text(
                    [
                      c.fullName,
                      if (c.isLoyal) '(fidèle)',
                      if (c.creditCents > 0) '· crédit ${formatDa(c.creditCents)}',
                    ].join(' '),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() {
              _customerId = v;
              _settleDebt = true;
            }),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(
          tooltip: 'Nouvelle cliente',
          onPressed: _newCustomer,
          icon: const Icon(Icons.person_add_alt),
        ),
      ]),
      if (customer != null && customer.creditCents > 0) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            color: AppColors.orangeBg,
            border: Border.all(color: AppColors.orangeLine),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            const Icon(Icons.account_balance_wallet_outlined, color: AppColors.orange, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Crédit en cours : ${formatDa(customer.creditCents)}',
                  style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w600)),
            ),
            const Text('Ajouter au ticket', style: TextStyle(color: AppColors.orange, fontSize: 13)),
            Switch(value: _settleDebt, onChanged: (v) => setState(() => _settleDebt = v)),
          ]),
        ),
      ],
      const SizedBox(height: 10),
      AppDropdown<String?>(
        value: _employeeId,
        label: 'Coiffeuse (pour les prochaines lignes)',
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('Aucune')),
          for (final e in _employees) DropdownMenuItem<String?>(value: e.id, child: Text(e.fullName)),
        ],
        onChanged: (v) => setState(() => _employeeId = v),
      ),
      const SizedBox(height: 6),
    ];
  }

  Widget _cartList({required bool shrink}) {
    if (_cart.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('Touchez une prestation pour l\'ajouter', style: TextStyle(color: AppColors.muted)),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: shrink,
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
    );
  }

  List<Widget> _ticketBottom() {
    final customer = _customer;
    final hasDebt = _debtIncluded > 0;
    return [
      const Divider(),
      KeyValueRow('Sous-total', formatDa(_subtotal)),
      if (_discount > 0) KeyValueRow('Remise fidélité', '-${formatDa(_discount)}'),
      if (hasDebt) ...[
        KeyValueRow('Total du ticket', formatDa(_total)),
        KeyValueRow('+ Ancien crédit', formatDa(_debtIncluded),
            style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w600)),
      ],
      const SizedBox(height: 4),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Expanded(
          child: Text(hasDebt ? 'À payer' : 'Total',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(formatDa(_due), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
        ),
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
      const SizedBox(height: 10),
      // Même largeur que la rangée des modes de paiement
      TextField(
        controller: _paidCtrl,
        decoration: InputDecoration(
          labelText: 'Montant reçu',
          hintText: 'Vide = ${formatDa(_due, suffix: false)} (montant exact)',
          suffixText: 'DA',
          errorText: _paidInvalid ? 'Montant invalide' : null,
          suffixIcon: _paidCtrl.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Effacer',
                  onPressed: () => setState(_paidCtrl.clear),
                  icon: const Icon(Icons.backspace_outlined, size: 18),
                ),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _quickButton('Exact', () => _setPaid(_due))),
        const SizedBox(width: 6),
        Expanded(child: _quickButton('+ 500', () => _addToPaid(50000))),
        const SizedBox(width: 6),
        Expanded(child: _quickButton('+ 1 000', () => _addToPaid(100000))),
        const SizedBox(width: 6),
        Expanded(child: _quickButton('+ 2 000', () => _addToPaid(200000))),
      ]),
      if (_paidInput != null && !_paidInvalid) ...[
        const SizedBox(height: 8),
        if (_change > 0)
          _infoLine('À rendre', formatDa(_change), Tone.green)
        else if (_remaining > 0)
          customer == null
              ? _infoLine('Reste dû ${formatDa(_remaining)}', 'choisissez la cliente', Tone.red)
              : _infoLine('Reste dû (crédit de ${customer.fullName})', formatDa(_remaining), Tone.orange),
      ],
      const SizedBox(height: 14),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        onPressed: _cart.isEmpty || _busy ? null : _checkout,
        icon: _busy
            ? const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.print_outlined),
        label: const Text('Encaisser et imprimer le reçu'),
      ),
    ];
  }

  Widget _quickButton(String label, VoidCallback onTap) => OutlinedButton(
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
        onPressed: onTap,
        child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
      );

  Widget _infoLine(String label, String value, Tone tone) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: toneBg(tone), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: toneFg(tone)))),
          Text(value, style: TextStyle(color: toneFg(tone), fontWeight: FontWeight.w700)),
        ]),
      );
}
