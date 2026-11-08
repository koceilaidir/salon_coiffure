import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../printing/receipt_printer.dart';
import '../theme.dart';
import '../util/money.dart';
import '../widgets/common.dart';

/// Écran 2 : le stock.
class StockScreen extends StatefulWidget {
  final VoidCallback onDataChanged;
  const StockScreen({super.key, required this.onDataChanged});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

enum _Filter { all, watch, sale }

class _StockScreenState extends State<StockScreen> {
  bool _loading = true;
  Object? _error;
  List<Product> _products = [];
  _Filter _filter = _Filter.all;
  String _search = '';

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
      final p = await repo.products();
      if (!mounted) return;
      setState(() {
        _products = p;
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

  Future<void> _changed() async {
    await _load();
    widget.onDataChanged();
  }

  List<Product> get _missing => _products.where((p) => p.status != StockStatus.ok).toList()
    ..sort((a, b) => a.status == b.status ? a.name.compareTo(b.name) : (a.status == StockStatus.out ? -1 : 1));

  List<Product> get _visible {
    final q = _search.toLowerCase();
    return _products.where((p) {
      if (q.isNotEmpty && !p.name.toLowerCase().contains(q) && !p.category.toLowerCase().contains(q)) return false;
      return switch (_filter) {
        _Filter.all => true,
        _Filter.watch => p.status != StockStatus.ok,
        _Filter.sale => p.forSale,
      };
    }).toList();
  }

  Future<void> _restock([Product? preset]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _RestockDialog(products: _products, preset: preset),
    );
    if (ok == true) _changed();
  }

  Future<void> _edit([Product? p]) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _ProductDialog(product: p));
    if (ok == true) _changed();
  }

  Future<void> _printOrder() async {
    try {
      final s = await repo.settings();
      await ReceiptPrinter.printOrder(settings: s, products: _missing);
      if (mounted) showInfo(context, 'Bon de commande imprimé.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _products.isEmpty || _error != null) {
      return LoadState(error: _error, onRetry: _load);
    }
    final value = _products.fold<int>(0, (a, p) => a + p.stockValueCents);
    final low = _products.where((p) => p.status == StockStatus.low).length;
    final out = _products.where((p) => p.status == StockStatus.out).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: 'Stock',
            subtitle: 'Déduit automatiquement à chaque prestation encaissée',
            actions: [
              OutlinedButton.icon(
                onPressed: _products.isEmpty ? null : () => _restock(),
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Entrée de marchandise'),
              ),
              FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Nouveau produit'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          StatRow(children: [
            StatCard(label: 'Références', value: '${_products.length}'),
            StatCard(label: 'Valeur du stock (prix d\'achat)', value: formatDa(value)),
            StatCard(label: 'Stock bas', value: '$low', tone: low > 0 ? Tone.orange : Tone.neutral),
            StatCard(label: 'En rupture', value: '$out', tone: out > 0 ? Tone.red : Tone.neutral),
          ]),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _list()),
                const SizedBox(width: 20),
                SizedBox(width: 320, child: _missingPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _list() {
    final rows = _visible;
    const head = TextStyle(fontSize: 12, color: AppColors.muted);
    return Panel(
      expand: true,
      title: 'Produits',
      trailing: Wrap(spacing: 8, children: [
        SizedBox(
          width: 200,
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: 'Rechercher'),
            onChanged: (v) => setState(() => _search = v.trim()),
          ),
        ),
        ChoicePill(label: 'Tous', selected: _filter == _Filter.all, onTap: () => setState(() => _filter = _Filter.all)),
        ChoicePill(label: 'À surveiller', selected: _filter == _Filter.watch, onTap: () => setState(() => _filter = _Filter.watch)),
        ChoicePill(label: 'En vente', selected: _filter == _Filter.sale, onTap: () => setState(() => _filter = _Filter.sale)),
      ]),
      child: Column(children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            Expanded(flex: 4, child: Text('Produit', style: head)),
            Expanded(flex: 2, child: Text('Catégorie', style: head)),
            Expanded(flex: 2, child: Text('Quantité', style: head, textAlign: TextAlign.right)),
            Expanded(flex: 2, child: Text('Seuil', style: head, textAlign: TextAlign.right)),
            SizedBox(width: 24),
            SizedBox(width: 90, child: Text('État', style: head)),
            SizedBox(width: 96),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('Aucun produit.', style: TextStyle(color: AppColors.muted)))
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = rows[i];
                    final (label, tone) = switch (p.status) {
                      StockStatus.out => ('Rupture', Tone.red),
                      StockStatus.low => ('Bas', Tone.orange),
                      StockStatus.ok => ('OK', Tone.green),
                    };
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(children: [
                        Expanded(
                          flex: 4,
                          child: Text(p.forSale ? '${p.name}  ·  ${formatDa(p.salePriceCents!)}' : p.name,
                              style: const TextStyle(fontWeight: FontWeight.w500)),
                        ),
                        Expanded(flex: 2, child: Text(p.category, style: const TextStyle(color: AppColors.muted))),
                        Expanded(
                          flex: 2,
                          child: Text('${formatQty(p.quantity)} ${p.unit}', textAlign: TextAlign.right),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(formatQty(p.minQuantity),
                              textAlign: TextAlign.right, style: const TextStyle(color: AppColors.muted)),
                        ),
                        const SizedBox(width: 24),
                        SizedBox(width: 90, child: Align(alignment: Alignment.centerLeft, child: StatusBadge(label, tone: tone))),
                        SizedBox(
                          width: 96,
                          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            IconButton(
                              tooltip: 'Entrée de marchandise',
                              onPressed: () => _restock(p),
                              icon: const Icon(Icons.add_box_outlined),
                            ),
                            IconButton(
                              tooltip: 'Modifier',
                              onPressed: () => _edit(p),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ]),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _missingPanel() {
    final missing = _missing;
    return Panel(
      expand: true,
      title: 'Ce qui manque',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Liste calculée à partir des seuils. Quantité proposée : de quoi revenir à deux fois le seuil.',
              style: TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 12),
          Expanded(
            child: missing.isEmpty
                ? const Center(child: Text('Rien à commander.', style: TextStyle(color: AppColors.green)))
                : ListView.separated(
                    itemCount: missing.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final p = missing[i];
                      final tone = p.status == StockStatus.out ? Tone.red : Tone.orange;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: toneBg(tone), borderRadius: BorderRadius.circular(10)),
                        child: Row(children: [
                          Expanded(child: Text(p.name, style: TextStyle(color: toneFg(tone)))),
                          Text('${formatQty(p.suggestedOrder)} ${p.unit}',
                              style: TextStyle(color: toneFg(tone), fontWeight: FontWeight.w700)),
                        ]),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent, width: 1.5),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: missing.isEmpty ? null : _printOrder,
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimer le bon de commande'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _RestockDialog extends StatefulWidget {
  final List<Product> products;
  final Product? preset;
  const _RestockDialog({required this.products, this.preset});

  @override
  State<_RestockDialog> createState() => _RestockDialogState();
}

class _RestockDialogState extends State<_RestockDialog> {
  String? _productId;
  final _qty = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _productId = widget.preset?.id;
  }

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final q = parseQty(_qty.text);
    if (_productId == null || q == null || q <= 0) {
      showError(context, Exception('Choisissez un produit et une quantité positive.'));
      return;
    }
    setState(() => _busy = true);
    try {
      await repo.stockEntry(_productId!, q, note: _note.text.trim());
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
    return AlertDialog(
      title: const Text('Entrée de marchandise'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _productId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Produit'),
            items: [
              for (final p in widget.products)
                DropdownMenuItem(value: p.id, child: Text('${p.name} (${formatQty(p.quantity)} ${p.unit})')),
            ],
            onChanged: (v) => setState(() => _productId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qty,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Quantité reçue'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (fournisseur, facture…)')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Ajouter au stock')),
      ],
    );
  }
}

class _ProductDialog extends StatefulWidget {
  final Product? product;
  const _ProductDialog({this.product});

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _category = TextEditingController(text: widget.product?.category ?? '');
  late final _unit = TextEditingController(text: widget.product?.unit ?? 'unité');
  late final _qty = TextEditingController(text: widget.product == null ? '0' : formatQty(widget.product!.quantity));
  late final _min = TextEditingController(text: widget.product == null ? '0' : formatQty(widget.product!.minQuantity));
  late final _cost = TextEditingController(text: widget.product == null ? '' : centsToInput(widget.product!.costCents));
  late final _sale = TextEditingController(
      text: widget.product?.salePriceCents == null ? '' : centsToInput(widget.product!.salePriceCents!));
  late bool _forSale = widget.product?.forSale ?? false;
  late bool _active = widget.product?.active ?? true;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _category, _unit, _qty, _min, _cost, _sale]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final qty = parseQty(_qty.text);
    final min = parseQty(_min.text);
    final cost = _cost.text.trim().isEmpty ? 0 : parseDa(_cost.text);
    final sale = _forSale ? parseDa(_sale.text) : null;
    if (name.isEmpty || qty == null || min == null || cost == null || (_forSale && sale == null)) {
      showError(context, Exception('Vérifiez le nom, les quantités et les prix.'));
      return;
    }
    final values = {
      'name': name,
      'category': _category.text.trim().isEmpty ? 'Divers' : _category.text.trim(),
      'unit': _unit.text.trim().isEmpty ? 'unité' : _unit.text.trim(),
      'min_quantity': min,
      'cost_cents': cost,
      'sale_price_cents': sale,
      'active': _active,
    };
    setState(() => _busy = true);
    try {
      final p = widget.product;
      if (p == null) {
        await repo.createProduct({...values, 'quantity': qty});
      } else {
        await repo.updateProduct(p.id, values);
        if ((qty - p.quantity).abs() > 0.0005) {
          await repo.stockEntry(p.id, qty - p.quantity, reason: 'adjustment', note: 'Inventaire');
        }
      }
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
    final editing = widget.product != null;
    return AlertDialog(
      title: Text(editing ? 'Modifier le produit' : 'Nouveau produit'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nom')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _category, decoration: const InputDecoration(labelText: 'Catégorie'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _unit, decoration: const InputDecoration(labelText: 'Unité (tube, flacon…)'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  decoration: InputDecoration(labelText: editing ? 'Quantité réelle (inventaire)' : 'Quantité de départ'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _min, decoration: const InputDecoration(labelText: 'Seuil d\'alerte'))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _cost, decoration: const InputDecoration(labelText: 'Prix d\'achat unitaire', suffixText: 'DA')),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vendu aux clientes'),
              value: _forSale,
              onChanged: (v) => setState(() => _forSale = v),
            ),
            if (_forSale)
              TextField(controller: _sale, decoration: const InputDecoration(labelText: 'Prix de vente', suffixText: 'DA')),
            if (editing)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Produit actif'),
                subtitle: const Text('Désactivez-le s\'il n\'est plus utilisé.'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Enregistrer')),
      ],
    );
  }
}
