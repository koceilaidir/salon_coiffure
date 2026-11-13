import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../hardware/hardware.dart';
import '../printing/receipt_printer.dart';
import '../theme.dart';
import '../util/money.dart';
import '../widgets/common.dart';

/// Écran 5 : réglages (salon, prestations, employées, clientes, matériels).
class SettingsScreen extends StatelessWidget {
  final Profile profile;
  final VoidCallback onDataChanged;
  const SettingsScreen({super.key, required this.profile, required this.onDataChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      return DefaultTabController(
        length: 5,
        child: Padding(
          padding: screenPadding(c.maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ScreenHeader(title: 'Réglages'),
              const SizedBox(height: 12),
              const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Salon'),
                  Tab(text: 'Prestations'),
                  Tab(text: 'Employées'),
                  Tab(text: 'Clientes'),
                  Tab(text: 'Matériels'),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(children: [
                  _SalonTab(profile: profile, onDataChanged: onDataChanged),
                  const _ServicesTab(),
                  const _EmployeesTab(),
                  const _CustomersTab(),
                  _HardwareTab(onDataChanged: onDataChanged),
                ]),
              ),
            ],
          ),
        ),
      );
    });
  }
}

// =============================== Salon ===============================

class _SalonTab extends StatefulWidget {
  final Profile profile;
  final VoidCallback onDataChanged;
  const _SalonTab({required this.profile, required this.onDataChanged});

  @override
  State<_SalonTab> createState() => _SalonTabState();
}

class _SalonTabState extends State<_SalonTab> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _discount = TextEditingController();
  final _points = TextEditingController();
  final _footer = TextEditingController();
  bool _loading = true;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _discount, _points, _footer]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await repo.settings();
      _name.text = s.salonName;
      _address.text = s.address;
      _phone.text = s.phone;
      _discount.text = formatQty(s.loyaltyDiscountPct);
      _points.text = '${s.pointsPer100Da}';
      _footer.text = s.receiptFooter;
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final pct = parseQty(_discount.text);
    final pts = int.tryParse(_points.text.trim());
    if (_name.text.trim().isEmpty || pct == null || pct < 0 || pct > 100 || pts == null || pts < 0) {
      showError(context, Exception('Vérifiez le nom, la remise (0 à 100 %) et les points.'));
      return;
    }
    setState(() => _busy = true);
    try {
      await repo.updateSettings({
        'salon_name': _name.text.trim(),
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
        'loyalty_discount_pct': pct,
        'points_per_100_da': pts,
        'receipt_footer': _footer.text.trim(),
      });
      widget.onDataChanged();
      if (mounted) showInfo(context, 'Réglages enregistrés.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _error != null) return LoadState(error: _error, onRetry: _load);
    final canEdit = widget.profile.isOwner;
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Panel(
            title: 'Informations imprimées sur les reçus',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!canEdit)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('Seul le propriétaire peut modifier ces informations.',
                      style: TextStyle(color: AppColors.muted)),
                ),
              TextField(controller: _name, enabled: canEdit, decoration: const InputDecoration(labelText: 'Nom du salon')),
              const SizedBox(height: 12),
              TextField(controller: _address, enabled: canEdit, decoration: const InputDecoration(labelText: 'Adresse')),
              const SizedBox(height: 12),
              TextField(controller: _phone, enabled: canEdit, decoration: const InputDecoration(labelText: 'Téléphone')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _discount,
                    enabled: canEdit,
                    decoration: const InputDecoration(labelText: 'Remise clientes fidèles', suffixText: '%'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _points,
                    enabled: canEdit,
                    decoration: const InputDecoration(labelText: 'Points fidélité par 100 DA'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                  controller: _footer, enabled: canEdit, decoration: const InputDecoration(labelText: 'Message en bas du reçu')),
              if (canEdit) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: PrimaryButton(label: 'Enregistrer', busy: _busy, onPressed: _save),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// ============================ Prestations ============================

class _ServicesTab extends StatefulWidget {
  const _ServicesTab();

  @override
  State<_ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<_ServicesTab> {
  List<Service> _items = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await repo.services(includeInactive: true);
      if (mounted) {
        setState(() {
          _items = s;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit([Service? s]) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _ServiceDialog(service: s));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty || _error != null) return LoadState(error: _error, onRetry: _load);
    return Panel(
      expand: true,
      title: 'Prestations (${_items.length})',
      trailing: FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Nouvelle prestation')),
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final s = _items[i];
          return ListTile(
            title: Text(s.name, style: TextStyle(color: s.active ? AppColors.ink : AppColors.muted)),
            subtitle: Text('${s.category} · ${s.durationLabel}${s.active ? '' : ' · désactivée'}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(formatDa(s.priceCents), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ]),
            onTap: () => _edit(s),
          );
        },
      ),
    );
  }
}

class _ServiceDialog extends StatefulWidget {
  final Service? service;
  const _ServiceDialog({this.service});

  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  late final _name = TextEditingController(text: widget.service?.name ?? '');
  late final _category = TextEditingController(text: widget.service?.category ?? 'Coiffure');
  late final _duration = TextEditingController(text: '${widget.service?.durationMin ?? 30}');
  late final _price = TextEditingController(text: widget.service == null ? '' : centsToInput(widget.service!.priceCents));
  late final _order = TextEditingController(text: '${widget.service?.sortOrder ?? 0}');
  late bool _active = widget.service?.active ?? true;

  List<Product> _products = [];

  /// id produit -> quantité consommée par prestation, en ml / g / pièces.
  final Map<String, TextEditingController> _consumption = {};
  bool _busy = false;
  bool _loadingConsumption = true;

  @override
  void initState() {
    super.initState();
    _loadConsumption();
  }

  Future<void> _loadConsumption() async {
    try {
      final products = await repo.products(includeInactive: true);
      final current = widget.service == null ? <String, double>{} : await repo.serviceConsumption(widget.service!.id);
      if (!mounted) return;
      setState(() {
        _products = products;
        for (final e in current.entries) {
          _consumption[e.key] = TextEditingController(text: formatQty(e.value));
        }
        _loadingConsumption = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingConsumption = false);
        showError(context, e);
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _category, _duration, _price, _order, ..._consumption.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Product? _product(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  String _unitOf(Product? p) => p == null ? '' : (p.contentUnit == 'pièce' ? 'pièce(s)' : p.contentUnit);

  Future<void> _addConsumption() async {
    final available = _products.where((p) => !_consumption.containsKey(p.id)).toList();
    if (available.isEmpty) return;
    final picked = await showDialog<Product>(
      context: context,
      builder: (c) => AppDialog(
        title: 'Produit consommé',
        subtitle: 'Choisissez le produit utilisé pendant la prestation.',
        width: 440,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final p in available)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(p.name),
              subtitle: Text(p.packagingLabel),
              trailing: const Icon(Icons.add_circle_outline, color: AppColors.accent),
              onTap: () => Navigator.pop(c, p),
            ),
        ]),
        actions: const [CancelButton()],
      ),
    );
    if (picked != null) {
      setState(() => _consumption[picked.id] = TextEditingController(text: picked.hasContent ? '' : '1'));
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final duration = int.tryParse(_duration.text.trim());
    final price = parseDa(_price.text);
    final order = int.tryParse(_order.text.trim()) ?? 0;
    final consumption = <String, double>{};
    for (final e in _consumption.entries) {
      final q = parseQty(e.value.text);
      if (q == null || q <= 0) {
        showError(context, Exception('Indiquez la quantité consommée pour ${_product(e.key)?.name ?? 'ce produit'}.'));
        return;
      }
      consumption[e.key] = q;
    }
    if (name.isEmpty || duration == null || price == null) {
      showError(context, Exception('Vérifiez le nom, la durée et le prix.'));
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await repo.saveService(widget.service?.id, {
        'name': name,
        'category': _category.text.trim().isEmpty ? 'Coiffure' : _category.text.trim(),
        'duration_min': duration,
        'price_cents': price,
        'sort_order': order,
        'active': _active,
      });
      await repo.setServiceConsumption(id, consumption);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.service == null ? 'Nouvelle prestation' : 'Modifier la prestation',
      width: 580,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nom')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _category,
              decoration: const InputDecoration(labelText: 'Catégorie (Coiffure, Couleur, Soins…)'),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: TextField(controller: _order, decoration: const InputDecoration(labelText: 'Ordre')),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(controller: _duration, decoration: const InputDecoration(labelText: 'Durée', suffixText: 'min')),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(controller: _price, decoration: const InputDecoration(labelText: 'Prix', suffixText: 'DA')),
          ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Proposée à la caisse'),
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
        const Divider(height: 24),
        Row(children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Produits consommés', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 2),
              Text(
                'Quantité moyenne utilisée pour UNE prestation. Elle est retirée du stock à chaque encaissement ; '
                'faites un constat dans Stock quand la réalité diffère.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _loadingConsumption ? null : _addConsumption,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter'),
          ),
        ]),
        const SizedBox(height: 8),
        if (_loadingConsumption)
          const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
        else if (_consumption.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Aucun produit lié.', style: TextStyle(color: AppColors.muted)),
          )
        else
          for (final e in _consumption.entries)
            Builder(builder: (context) {
              final p = _product(e.key);
              final q = parseQty(e.value.text);
              final perBottle = (p != null && p.hasContent && q != null && q > 0) ? p.contentAmount / q : null;
              return Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.lineSoft),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p?.name ?? 'Produit', style: const TextStyle(fontWeight: FontWeight.w500)),
                      Text(
                        [
                          if (p != null) p.packagingLabel,
                          if (perBottle != null) '≈ ${perBottle.floor()} prestations par ${p!.unit}',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ]),
                  ),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: e.value,
                      decoration: InputDecoration(labelText: 'Par prestation', suffixText: _unitOf(p)),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Retirer',
                    onPressed: () => setState(() => _consumption.remove(e.key)?.dispose()),
                    icon: const Icon(Icons.close),
                  ),
                ]),
              );
            }),
      ]),
      actions: [
        const CancelButton(),
        PrimaryButton(label: 'Enregistrer', busy: _busy, onPressed: _loadingConsumption ? null : _save),
      ],
    );
  }
}

// ============================= Employées =============================

class _EmployeesTab extends StatefulWidget {
  const _EmployeesTab();

  @override
  State<_EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends State<_EmployeesTab> {
  List<Employee> _items = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final e = await repo.employees(includeInactive: true);
      if (mounted) {
        setState(() {
          _items = e;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit([Employee? e]) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _EmployeeDialog(employee: e));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty || _error != null) return LoadState(error: _error, onRetry: _load);
    return Panel(
      expand: true,
      title: 'Employées (${_items.length})',
      trailing: FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Nouvelle employée')),
      child: _items.isEmpty
          ? const Center(child: Text('Ajoutez les coiffeuses du salon.', style: TextStyle(color: AppColors.muted)))
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final e = _items[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.accentSoft,
                    foregroundColor: AppColors.accent,
                    child: Text(e.fullName.isEmpty ? '?' : e.fullName[0].toUpperCase()),
                  ),
                  title: Text(e.fullName, style: TextStyle(color: e.active ? AppColors.ink : AppColors.muted)),
                  subtitle: Text('Fixe ${formatDa(e.baseSalaryCents)} · commission ${formatQty(e.commissionPct)} %'
                      '${e.active ? '' : ' · ne travaille plus au salon'}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _edit(e),
                );
              },
            ),
    );
  }
}

class _EmployeeDialog extends StatefulWidget {
  final Employee? employee;
  const _EmployeeDialog({this.employee});

  @override
  State<_EmployeeDialog> createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends State<_EmployeeDialog> {
  late final _name = TextEditingController(text: widget.employee?.fullName ?? '');
  late final _base = TextEditingController(text: widget.employee == null ? '' : centsToInput(widget.employee!.baseSalaryCents));
  late final _commission = TextEditingController(text: formatQty(widget.employee?.commissionPct ?? 0));
  late bool _active = widget.employee?.active ?? true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _base.dispose();
    _commission.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final base = _base.text.trim().isEmpty ? 0 : parseDa(_base.text);
    final pct = parseQty(_commission.text);
    if (_name.text.trim().isEmpty || base == null || pct == null || pct < 0 || pct > 100) {
      showError(context, Exception('Vérifiez le nom, le salaire et la commission (0 à 100 %).'));
      return;
    }
    setState(() => _busy = true);
    try {
      await repo.saveEmployee(widget.employee?.id, {
        'full_name': _name.text.trim(),
        'base_salary_cents': base,
        'commission_pct': pct,
        'active': _active,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.employee == null ? 'Nouvelle employée' : 'Modifier l\'employée',
      width: 500,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nom')),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
                controller: _base, decoration: const InputDecoration(labelText: 'Salaire fixe mensuel', suffixText: 'DA')),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _commission,
              decoration: const InputDecoration(
                labelText: 'Commission',
                suffixText: '%',
                helperText: 'Sur ses prestations du mois',
              ),
            ),
          ),
        ]),
        if (widget.employee != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Travaille au salon'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
      ]),
      actions: [
        const CancelButton(),
        PrimaryButton(label: 'Enregistrer', busy: _busy, onPressed: _save),
      ],
    );
  }
}

// ============================== Clientes =============================

/// Fiche cliente : création, modification, crédit et remboursements.
/// Utilisée aussi par la caisse pour créer une cliente.
Future<Customer?> showCustomerDialog(BuildContext context, {Customer? customer}) {
  return showDialog<Customer>(context: context, builder: (_) => _CustomerDialog(customer: customer));
}

class _CustomerDialog extends StatefulWidget {
  final Customer? customer;
  const _CustomerDialog({this.customer});

  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  late final _name = TextEditingController(text: widget.customer?.fullName ?? '');
  late final _phone = TextEditingController(text: widget.customer?.phone ?? '');
  late bool _loyal = widget.customer?.isLoyal ?? false;
  late Customer? _current = widget.customer;
  final _repay = TextEditingController();
  String _repayMethod = 'cash';
  List<CreditMovement> _history = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _repay.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final c = _current;
    if (c == null) return;
    try {
      final h = await repo.creditHistory(c.id);
      if (mounted) setState(() => _history = h);
    } catch (_) {
      // L'historique est un plus ; la fiche reste utilisable sans.
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showError(context, Exception('Saisissez le nom de la cliente.'));
      return;
    }
    setState(() => _busy = true);
    try {
      final c = await repo.saveCustomer(_current?.id, {
        'full_name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'is_loyal': _loyal,
      });
      if (mounted) Navigator.pop(context, c);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _doRepay() async {
    final c = _current;
    final amount = parseDa(_repay.text);
    if (c == null || amount == null || amount <= 0) {
      showError(context, Exception('Saisissez le montant remboursé.'));
      return;
    }
    if (amount > c.creditCents) {
      showError(context, Exception('Le montant dépasse le crédit (${formatDa(c.creditCents)}).'));
      return;
    }
    setState(() => _busy = true);
    try {
      final updated = await repo.repayCredit(customerId: c.id, amountCents: amount, paymentMethod: _repayMethod);
      if (!mounted) return;
      setState(() {
        _current = updated;
        _repay.clear();
        _busy = false;
      });
      showInfo(context, 'Remboursement de ${formatDa(amount)} enregistré.');
      _loadHistory();
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _current;
    return AppDialog(
      title: c == null ? 'Nouvelle cliente' : c.fullName,
      subtitle: c == null ? null : '${c.loyaltyPoints} points fidélité',
      width: 560,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _name, autofocus: c == null, decoration: const InputDecoration(labelText: 'Nom')),
        const SizedBox(height: 12),
        TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Téléphone')),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Cliente fidèle'),
          subtitle: const Text('Bénéficie de la remise fidélité réglée dans « Salon ».'),
          value: _loyal,
          onChanged: (v) => setState(() => _loyal = v),
        ),
        if (c != null) ...[
          const Divider(height: 28),
          Row(children: [
            const Expanded(child: Text('Crédit', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
            StatusBadge(
              c.creditCents > 0 ? 'Doit ${formatDa(c.creditCents)}' : 'Aucun crédit',
              tone: c.creditCents > 0 ? Tone.orange : Tone.green,
            ),
          ]),
          if (c.creditCents > 0) ...[
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _repay,
                  decoration: const InputDecoration(labelText: 'Montant remboursé', suffixText: 'DA'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: AppDropdown<String>(
                  value: _repayMethod,
                  label: 'Payé en',
                  items: [for (final e in saleMethods.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _repayMethod = v ?? 'cash'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              TextButton(
                onPressed: () => setState(() => _repay.text = centsToInput(c.creditCents)),
                child: const Text('Tout rembourser'),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _busy ? null : _doRepay,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Encaisser le remboursement'),
              ),
            ]),
          ],
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Historique', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 4),
            for (final m in _history)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(width: 92, child: Text(DateFormat('dd/MM/yy HH:mm').format(m.at), style: const TextStyle(fontSize: 12))),
                  Expanded(
                    child: Text(m.note.isEmpty ? m.kindLabel : m.note,
                        style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                  ),
                  Text(
                    '${m.deltaCents > 0 ? '+' : ''}${formatDa(m.deltaCents)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: m.deltaCents > 0 ? AppColors.orange : AppColors.green,
                    ),
                  ),
                ]),
              ),
          ],
        ],
      ]),
      actions: [
        CancelButton(label: c == null ? 'Annuler' : 'Fermer'),
        PrimaryButton(label: 'Enregistrer', busy: _busy, onPressed: _save),
      ],
    );
  }
}

class _CustomersTab extends StatefulWidget {
  const _CustomersTab();

  @override
  State<_CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends State<_CustomersTab> {
  List<Customer> _items = [];
  bool _loading = true;
  Object? _error;
  String _search = '';
  bool _onlyCredit = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await repo.customers();
      if (mounted) {
        setState(() {
          _items = c;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit([Customer? c]) async {
    await showCustomerDialog(context, customer: c);
    _load(); // un remboursement a pu changer le crédit même sans « Enregistrer »
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty || _error != null) return LoadState(error: _error, onRetry: _load);
    final q = _search.toLowerCase();
    final list = _items
        .where((c) => q.isEmpty || c.fullName.toLowerCase().contains(q) || c.phone.contains(q))
        .where((c) => !_onlyCredit || c.creditCents > 0)
        .toList();
    final totalCredit = _items.fold<int>(0, (a, c) => a + c.creditCents);
    return Panel(
      expand: true,
      title: 'Clientes (${_items.length})',
      trailing: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 220,
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: 'Nom ou téléphone'),
            onChanged: (v) => setState(() => _search = v.trim()),
          ),
        ),
        ChoicePill(
          label: totalCredit > 0 ? 'Avec crédit (${formatDa(totalCredit)})' : 'Avec crédit',
          selected: _onlyCredit,
          onTap: () => setState(() => _onlyCredit = !_onlyCredit),
        ),
        FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Nouvelle cliente')),
      ]),
      child: list.isEmpty
          ? const Center(child: Text('Aucune cliente.', style: TextStyle(color: AppColors.muted)))
          : ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = list[i];
                return ListTile(
                  title: Text(c.fullName),
                  subtitle: Text(c.phone.isEmpty ? '—' : c.phone),
                  trailing: Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (c.creditCents > 0) StatusBadge('Crédit ${formatDa(c.creditCents)}', tone: Tone.orange),
                    if (c.isLoyal) const StatusBadge('Fidèle', tone: Tone.green),
                    Text('${c.loyaltyPoints} pts'),
                    const Icon(Icons.chevron_right),
                  ]),
                  onTap: () => _edit(c),
                );
              },
            ),
    );
  }
}

// ============================= Matériels =============================

class _HardwareTab extends StatefulWidget {
  final VoidCallback onDataChanged;
  const _HardwareTab({required this.onDataChanged});

  @override
  State<_HardwareTab> createState() => _HardwareTabState();
}

class _HardwareTabState extends State<_HardwareTab> {
  List<Printer> _printers = [];
  String? _selected;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ReceiptPrinter.available();
      final sel = await ReceiptPrinter.selectedUrl();
      if (mounted) {
        setState(() {
          _printers = list;
          _selected = sel;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _choose(Printer p) async {
    await ReceiptPrinter.select(p);
    setState(() => _selected = p.url);
    widget.onDataChanged();
  }

  Future<void> _testPrint() async {
    try {
      final s = await repo.settings();
      await ReceiptPrinter.printTest(s);
      if (mounted) showInfo(context, 'Ticket de test envoyé.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _testDrawer() async {
    try {
      await Hardware.openDrawer();
      if (mounted) showInfo(context, 'Commande d\'ouverture envoyée au tiroir.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _section({required IconData icon, required String title, required String text, required List<Widget> children}) {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(child: SectionTitle(title)),
        ]),
        const SizedBox(height: 8),
        Text(text, style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 8),
        ...children,
      ]),
    );
  }

  Widget _radioRow({required bool selected, required String title, String? subtitle, required VoidCallback onTap}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? AppColors.accent : AppColors.muted,
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _error != null) return LoadState(error: _error, onRetry: _load);
    final sections = <Widget>[
      _section(
        icon: Icons.print_outlined,
        title: 'Imprimante de tickets (58 mm)',
        text: 'Branchez l\'imprimante en USB et installez son pilote Windows, puis choisissez-la. '
            'Le choix est mémorisé sur ce PC.',
        children: [
          if (_printers.isEmpty)
            const Text('Aucune imprimante trouvée sur ce PC.', style: TextStyle(color: AppColors.red))
          else
            for (final p in _printers)
              _radioRow(
                selected: _selected == p.url,
                title: p.name,
                subtitle: p.isDefault ? 'Imprimante par défaut de Windows' : null,
                onTap: () => _choose(p),
              ),
          Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
            TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Actualiser')),
            OutlinedButton.icon(
              onPressed: _selected == null ? null : _testPrint,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Ticket de test'),
            ),
          ]),
        ],
      ),
      _section(
        icon: Icons.inbox_outlined,
        title: 'Tiroir-caisse',
        text: 'Le tiroir est branché sur l\'imprimante de tickets (prise RJ11). '
            'C\'est l\'imprimante qui l\'ouvre.',
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tiroir-caisse branché'),
            subtitle: const Text('Affiche le bouton « Ouvrir le tiroir » dans la caisse.'),
            value: Hardware.drawerEnabled,
            onChanged: (v) async {
              await Hardware.setDrawerEnabled(v);
              setState(() {});
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ouvrir à chaque paiement en espèces'),
            value: Hardware.drawerAutoOnCash,
            onChanged: Hardware.drawerEnabled
                ? (v) async {
                    await Hardware.setDrawerAuto(v);
                    setState(() {});
                  }
                : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: Hardware.drawerEnabled && _selected != null ? _testDrawer : null,
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Tester l\'ouverture'),
            ),
          ),
        ],
      ),
      _section(
        icon: Icons.tv_outlined,
        title: 'Afficheur client',
        text: 'Montre le ticket et le total à la cliente. '
            'Le branchement sera activé quand le modèle d\'afficheur sera choisi.',
        children: [
          for (final e in customerDisplayTypes.entries)
            _radioRow(
              selected: Hardware.customerDisplay == e.key,
              title: e.value,
              subtitle: e.key == 'none' ? null : 'Bientôt disponible',
              onTap: () async {
                await Hardware.setCustomerDisplay(e.key);
                setState(() {});
              },
            ),
        ],
      ),
      _section(
        icon: Icons.touch_app_outlined,
        title: 'PC tactile',
        text: 'Agrandit les boutons et les champs pour une utilisation au doigt.',
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: Hardware.touchMode,
            builder: (context, touch, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mode tactile'),
              value: touch,
              onChanged: Hardware.setTouchMode,
            ),
          ),
        ],
      ),
    ];

    return LayoutBuilder(builder: (context, c) {
      final twoCols = c.maxWidth >= 1000;
      final w = twoCols ? (c.maxWidth - 16) / 2 : c.maxWidth;
      return SingleChildScrollView(
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [for (final s in sections) SizedBox(width: w, child: s)],
        ),
      );
    });
  }
}
