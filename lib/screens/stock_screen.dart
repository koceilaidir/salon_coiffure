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

  /// Quantités du bon de commande modifiées à la main (id produit -> quantité).
  final Map<String, double> _orderQty = {};

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

  double _qtyToOrder(Product p) => _orderQty[p.id] ?? p.suggestedOrder;

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

  Future<void> _count(Product p) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _CountDialog(product: p));
    if (ok == true) _changed();
  }

  Future<void> _edit([Product? p]) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _ProductDialog(product: p));
    if (ok == true) _changed();
  }

  Future<void> _printOrder() async {
    final order = [
      for (final p in _missing)
        if (_qtyToOrder(p) > 0) (p, _qtyToOrder(p)),
    ];
    if (order.isEmpty) {
      showError(context, Exception('Toutes les quantités sont à zéro.'));
      return;
    }
    try {
      final s = await repo.settings();
      await ReceiptPrinter.printOrder(settings: s, order: order);
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

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 1100;
      final gap = gapFor(c.maxWidth);
      final header = [
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
        SizedBox(height: gap),
        StatRow(children: [
          StatCard(label: 'Références', value: '${_products.length}'),
          StatCard(label: 'Valeur du stock (prix d\'achat)', value: formatDa(value)),
          StatCard(label: 'Stock bas', value: '$low', tone: low > 0 ? Tone.orange : Tone.neutral),
          StatCard(label: 'En rupture', value: '$out', tone: out > 0 ? Tone.red : Tone.neutral),
        ]),
        SizedBox(height: gap),
      ];

      if (wide) {
        return Padding(
          padding: screenPadding(c.maxWidth),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ...header,
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _list()),
                SizedBox(width: gap),
                SizedBox(width: 340, child: _missingPanel(expand: true)),
              ]),
            ),
          ]),
        );
      }
      return SingleChildScrollView(
        padding: screenPadding(c.maxWidth),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ...header,
          _missingPanel(expand: false),
          SizedBox(height: gap),
          SizedBox(height: 560, child: _list()),
        ]),
      );
    });
  }

  Widget _list() {
    final rows = _visible;
    const head = TextStyle(fontSize: 12, color: AppColors.muted);
    return Panel(
      expand: true,
      title: 'Produits',
      trailing: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 200,
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: 'Rechercher…'),
            onChanged: (v) => setState(() => _search = v.trim()),
          ),
        ),
        ChoicePill(label: 'Tous', selected: _filter == _Filter.all, onTap: () => setState(() => _filter = _Filter.all)),
        ChoicePill(
            label: 'À surveiller',
            selected: _filter == _Filter.watch,
            onTap: () => setState(() => _filter = _Filter.watch)),
        ChoicePill(
            label: 'En vente', selected: _filter == _Filter.sale, onTap: () => setState(() => _filter = _Filter.sale)),
      ]),
      child: LayoutBuilder(builder: (context, c) {
        final showCategory = c.maxWidth >= 720;
        final showMin = c.maxWidth >= 560;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              const Expanded(flex: 4, child: Text('Produit', style: head)),
              if (showCategory) const Expanded(flex: 2, child: Text('Catégorie', style: head)),
              const Expanded(flex: 3, child: Text('En stock', style: head, textAlign: TextAlign.right)),
              if (showMin) const SizedBox(width: 70, child: Text('Seuil', style: head, textAlign: TextAlign.right)),
              const SizedBox(width: 16),
              const SizedBox(width: 78, child: Text('État', style: head)),
              const SizedBox(width: 132),
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
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                              Text(
                                [
                                  p.packagingLabel,
                                  if (p.forSale) 'vente ${formatDa(p.salePriceCents!)}',
                                ].join(' · '),
                                style: const TextStyle(fontSize: 12, color: AppColors.muted),
                              ),
                            ]),
                          ),
                          if (showCategory)
                            Expanded(flex: 2, child: Text(p.category, style: const TextStyle(color: AppColors.muted))),
                          Expanded(flex: 3, child: Text(p.stockLabel, textAlign: TextAlign.right)),
                          if (showMin)
                            SizedBox(
                              width: 70,
                              child: Text(formatQty(p.minQuantity),
                                  textAlign: TextAlign.right, style: const TextStyle(color: AppColors.muted)),
                            ),
                          const SizedBox(width: 16),
                          SizedBox(
                              width: 78,
                              child: Align(alignment: Alignment.centerLeft, child: StatusBadge(label, tone: tone))),
                          SizedBox(
                            width: 132,
                            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                              IconButton(
                                tooltip: 'Entrée de marchandise',
                                onPressed: () => _restock(p),
                                icon: const Icon(Icons.add_box_outlined),
                              ),
                              IconButton(
                                tooltip: 'Constat (recompter le stock)',
                                onPressed: () => _count(p),
                                icon: const Icon(Icons.fact_check_outlined),
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
        ]);
      }),
    );
  }

  Widget _missingPanel({required bool expand}) {
    final missing = _missing;
    final rows = [
      for (final p in missing)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          decoration: BoxDecoration(
            color: toneBg(p.status == StockStatus.out ? Tone.red : Tone.orange),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: TextStyle(color: toneFg(p.status == StockStatus.out ? Tone.red : Tone.orange))),
                Text('Reste : ${p.stockLabel}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ]),
            ),
            QtyStepper(
              value: _qtyToOrder(p),
              format: formatQty,
              onChanged: (v) => setState(() => _orderQty[p.id] = v),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 52,
              child: Text(p.unit, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ),
          ]),
        ),
    ];
    final list = missing.isEmpty
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('Rien à commander.', style: TextStyle(color: AppColors.green))),
          )
        : (expand ? ListView(children: rows) : Column(children: rows));

    return Panel(
      expand: expand,
      title: 'Ce qui manque',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Quantité proposée : de quoi revenir à deux fois le seuil. Ajustez-la avec − / + avant d\'imprimer.',
              style: TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 12),
          if (expand) Expanded(child: list) else list,
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
// Entrée de marchandise
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

  Product? get _product {
    for (final p in widget.products) {
      if (p.id == _productId) return p;
    }
    return null;
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
    final p = _product;
    return AppDialog(
      title: 'Entrée de marchandise',
      subtitle: 'Ajoute les conditionnements reçus au stock.',
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        AppDropdown<String>(
          value: _productId,
          label: 'Produit',
          items: [
            for (final p in widget.products) DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: (v) => setState(() => _productId = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _qty,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Quantité reçue',
            suffixText: p == null ? null : p.unit,
            helperText: p == null ? null : '${p.packagingLabel} · en stock : ${p.stockLabel}',
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (fournisseur, facture…)')),
      ]),
      actions: [
        const CancelButton(),
        PrimaryButton(label: 'Ajouter au stock', busy: _busy, onPressed: _save),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Constat : recompter le stock réel
// ---------------------------------------------------------------------------

class _CountDialog extends StatefulWidget {
  final Product product;
  const _CountDialog({required this.product});

  @override
  State<_CountDialog> createState() => _CountDialogState();
}

class _CountDialogState extends State<_CountDialog> {
  late final _full = TextEditingController(text: '${widget.product.split.full}');
  late final _rest = TextEditingController(
      text: widget.product.split.rest == 0 ? '' : formatQty(widget.product.split.rest));
  late final _qty = TextEditingController(text: formatQty(widget.product.quantity < 0 ? 0 : widget.product.quantity));
  bool _busy = false;

  @override
  void dispose() {
    _full.dispose();
    _rest.dispose();
    _qty.dispose();
    super.dispose();
  }

  /// Nouvelle quantité en conditionnements (null si saisie invalide).
  double? get _newQty {
    final p = widget.product;
    if (!p.hasContent) return parseQty(_qty.text);
    final full = parseQty(_full.text.isEmpty ? '0' : _full.text);
    final rest = parseQty(_rest.text.isEmpty ? '0' : _rest.text);
    if (full == null || rest == null || full < 0 || rest < 0 || rest >= p.contentAmount) return null;
    return full + rest / p.contentAmount;
  }

  Future<void> _save() async {
    final p = widget.product;
    final q = _newQty;
    if (q == null || q < 0) {
      showError(context,
          Exception(p.hasContent ? 'Le reste doit être inférieur à ${p.contentLabel}.' : 'Quantité invalide.'));
      return;
    }
    final delta = q - p.quantity;
    if (delta.abs() < 0.000001) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _busy = true);
    try {
      await repo.stockEntry(p.id, delta, reason: 'adjustment', note: 'Constat');
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
    final p = widget.product;
    final q = _newQty;
    final diff = q == null ? null : q - p.quantity;
    return AppDialog(
      title: 'Constat — ${p.name}',
      subtitle: 'Comptez ce qu\'il reste vraiment. Le logiciel s\'ajuste sur votre comptage.',
      content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        KeyValueRow('Selon le logiciel', p.stockLabel),
        const SizedBox(height: 14),
        if (p.hasContent)
          Row(children: [
            Expanded(
              child: TextField(
                controller: _full,
                autofocus: true,
                decoration: InputDecoration(labelText: '${p.unit} pleins', helperText: p.packagingLabel),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _rest,
                decoration: InputDecoration(
                  labelText: 'Reste du ${p.unit} entamé',
                  suffixText: p.contentUnit == 'pièce' ? 'pièces' : p.contentUnit,
                  helperText: 'Ex. 350 sur ${p.contentLabel}',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ])
        else
          TextField(
            controller: _qty,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Quantité réelle', suffixText: p.unit),
            onChanged: (_) => setState(() {}),
          ),
        const SizedBox(height: 14),
        if (diff != null && diff.abs() >= 0.000001)
          Text(
            diff > 0
                ? 'Il y a plus que prévu : +${formatQty(diff)} ${p.unit}.'
                : 'Il y a moins que prévu : ${formatQty(diff)} ${p.unit} (consommation plus forte, perte…).',
            style: TextStyle(color: diff > 0 ? AppColors.green : AppColors.orange, fontWeight: FontWeight.w600),
          ),
      ]),
      actions: [
        const CancelButton(),
        PrimaryButton(label: 'Enregistrer le constat', busy: _busy, onPressed: _save),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Créer / modifier un produit
// ---------------------------------------------------------------------------

/// Unités proposées pour la contenance, et leur conversion vers la base (ml, g, pièce).
const _contentChoices = <String, (String, double)>{
  'ml': ('ml', 1.0),
  'L': ('ml', 1000.0),
  'g': ('g', 1.0),
  'kg': ('g', 1000.0),
  'pièce(s)': ('pièce', 1.0),
};

class _ProductDialog extends StatefulWidget {
  final Product? product;
  const _ProductDialog({this.product});

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _category = TextEditingController(text: widget.product?.category ?? '');
  late final _unit = TextEditingController(text: widget.product?.unit ?? 'flacon');
  late final _content = TextEditingController();
  late final _qty = TextEditingController(text: '0');
  late final _min = TextEditingController(text: widget.product == null ? '0' : formatQty(widget.product!.minQuantity));
  late final _cost = TextEditingController(text: widget.product == null ? '' : centsToInput(widget.product!.costCents));
  late final _sale = TextEditingController(
      text: widget.product?.salePriceCents == null ? '' : centsToInput(widget.product!.salePriceCents!));
  late bool _forSale = widget.product?.forSale ?? false;
  late bool _active = widget.product?.active ?? true;
  String _contentUnitChoice = 'ml';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p == null) {
      _content.text = '1000';
    } else if (p.contentUnit == 'ml' && p.contentAmount >= 1000) {
      _contentUnitChoice = 'L';
      _content.text = formatQty(p.contentAmount / 1000);
    } else if (p.contentUnit == 'g' && p.contentAmount >= 1000) {
      _contentUnitChoice = 'kg';
      _content.text = formatQty(p.contentAmount / 1000);
    } else {
      _contentUnitChoice = p.contentUnit == 'pièce' ? 'pièce(s)' : p.contentUnit;
      _content.text = formatQty(p.contentAmount);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _category, _unit, _content, _qty, _min, _cost, _sale]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final qty = parseQty(_qty.text);
    final min = parseQty(_min.text);
    final content = parseQty(_content.text);
    final cost = _cost.text.trim().isEmpty ? 0 : parseDa(_cost.text);
    final sale = _forSale ? parseDa(_sale.text) : null;
    if (name.isEmpty || qty == null || min == null || cost == null || (_forSale && sale == null)) {
      showError(context, Exception('Vérifiez le nom, les quantités et les prix.'));
      return;
    }
    if (content == null || content <= 0) {
      showError(context, Exception('Indiquez la contenance (ex. 1 L, 500 ml, 100 pièces).'));
      return;
    }
    final (baseUnit, factor) = _contentChoices[_contentUnitChoice]!;
    final values = {
      'name': name,
      'category': _category.text.trim().isEmpty ? 'Divers' : _category.text.trim(),
      'unit': _unit.text.trim().isEmpty ? 'unité' : _unit.text.trim(),
      'content_amount': content * factor,
      'content_unit': baseUnit,
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
    final unit = _unit.text.trim().isEmpty ? 'conditionnement' : _unit.text.trim();
    return AppDialog(
      title: editing ? 'Modifier le produit' : 'Nouveau produit',
      width: 560,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nom (ex. Shampoing kératine)')),
        const SizedBox(height: 12),
        TextField(controller: _category, decoration: const InputDecoration(labelText: 'Catégorie (Couleur, Soins…)')),
        const SizedBox(height: 18),
        const Text('Conditionnement', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _unit,
              decoration: const InputDecoration(labelText: 'Type (flacon, tube, pot…)'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: TextField(controller: _content, decoration: const InputDecoration(labelText: 'Contenance')),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: AppDropdown<String>(
              value: _contentUnitChoice,
              label: 'Unité',
              items: [for (final k in _contentChoices.keys) DropdownMenuItem(value: k, child: Text(k))],
              onChanged: (v) => setState(() => _contentUnitChoice = v ?? 'ml'),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        const Text(
          'La consommation des prestations se règle ensuite en ml / g / pièces (Réglages > Prestations).',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        Row(children: [
          if (!editing) ...[
            Expanded(
              child: TextField(
                controller: _qty,
                decoration: InputDecoration(labelText: 'Stock de départ', suffixText: unit),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: TextField(
              controller: _min,
              decoration: InputDecoration(labelText: 'Seuil d\'alerte', suffixText: unit),
            ),
          ),
        ]),
        if (editing)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Pour corriger la quantité en stock, utilisez « Constat » dans la liste.',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _cost,
          decoration: InputDecoration(labelText: 'Prix d\'achat (par $unit)', suffixText: 'DA'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Vendu aux clientes'),
          value: _forSale,
          onChanged: (v) => setState(() => _forSale = v),
        ),
        if (_forSale)
          TextField(
            controller: _sale,
            decoration: InputDecoration(labelText: 'Prix de vente (par $unit)', suffixText: 'DA'),
          ),
        if (editing)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Produit actif'),
            subtitle: const Text('Désactivez-le s\'il n\'est plus utilisé.'),
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
