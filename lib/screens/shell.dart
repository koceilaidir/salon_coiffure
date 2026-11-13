import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../printing/receipt_printer.dart';
import '../theme.dart';
import 'accounting_screen.dart';
import 'expenses_screen.dart';
import 'pos_screen.dart';
import 'settings_screen.dart';
import 'stock_screen.dart';

/// Fenêtre principale : menu de gauche + écran sélectionné.
class Shell extends StatefulWidget {
  final Profile profile;
  const Shell({super.key, required this.profile});

  @override
  State<Shell> createState() => _ShellState();
}

class _NavItem {
  final IconData icon;
  final String label;
  final String short;
  const _NavItem(this.icon, this.label, this.short);
}

const _items = [
  _NavItem(Icons.point_of_sale_outlined, 'Caisse', 'Caisse'),
  _NavItem(Icons.inventory_2_outlined, 'Stock', 'Stock'),
  _NavItem(Icons.receipt_long_outlined, 'Dépenses & factures', 'Dépenses'),
  _NavItem(Icons.bar_chart_outlined, 'Comptabilité & paie', 'Compta'),
  _NavItem(Icons.settings_outlined, 'Réglages', 'Réglages'),
];

class _ShellState extends State<Shell> {
  int _index = 0;
  int _lowStock = 0;
  String _salonName = '';
  String? _printerName;

  @override
  void initState() {
    super.initState();
    _refreshSidebar();
  }

  Future<void> _refreshSidebar() async {
    try {
      final results = await Future.wait([
        repo.lowStockCount(),
        repo.settings(),
        ReceiptPrinter.selectedName(),
      ]);
      if (!mounted) return;
      setState(() {
        _lowStock = results[0] as int;
        _salonName = (results[1] as SalonSettings).salonName;
        _printerName = results[2] as String?;
      });
    } catch (_) {
      // Le menu reste utilisable même si ces infos ne chargent pas.
    }
  }

  void _go(int i) {
    setState(() => _index = i);
    _refreshSidebar();
  }

  Widget _screen() {
    switch (_index) {
      case 0:
        return PosScreen(profile: widget.profile, onDataChanged: _refreshSidebar);
      case 1:
        return StockScreen(onDataChanged: _refreshSidebar);
      case 2:
        return const ExpensesScreen();
      case 3:
        return AccountingScreen(profile: widget.profile);
      default:
        return SettingsScreen(profile: widget.profile, onDataChanged: _refreshSidebar);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(builder: (context, c) {
        // Menu complet sur grand écran, réduit aux icônes sinon.
        final compact = c.maxWidth < 1150;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Sidebar(
              index: _index,
              onSelect: _go,
              lowStock: _lowStock,
              salonName: _salonName,
              profile: widget.profile,
              printerName: _printerName,
              compact: compact,
            ),
            Expanded(
              child: KeyedSubtree(key: ValueKey(_index), child: _screen()),
            ),
          ],
        );
      }),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final int lowStock;
  final String salonName;
  final Profile profile;
  final String? printerName;
  final bool compact;

  const _Sidebar({
    required this.index,
    required this.onSelect,
    required this.lowStock,
    required this.salonName,
    required this.profile,
    required this.printerName,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) return _rail(context);
    return Container(
      width: 240,
      color: AppColors.sidebar,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.sidebarMuted),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Text('LOGO', style: TextStyle(fontSize: 9, color: AppColors.sidebarMuted)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(salonName.isEmpty ? 'Salon' : salonName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  Text('${profile.roleLabel} · ${profile.fullName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.sidebarMuted, fontSize: 12)),
                ]),
              ),
            ]),
          ),
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _NavButton(
                item: _items[i],
                selected: i == index,
                badge: i == 1 && lowStock > 0 ? lowStock : null,
                onTap: () => onSelect(i),
              ),
            ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.sidebarSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Icon(Icons.print_outlined,
                  size: 16, color: printerName == null ? AppColors.badge : const Color(0xFF34D399)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(printerName ?? 'Imprimante non choisie',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.sidebarMuted, fontSize: 12)),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: repo.signOut,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.sidebarMuted,
              alignment: Alignment.centerLeft,
              minimumSize: const Size(44, 44),
            ),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
  }

  Widget _rail(BuildContext context) {
    return Container(
      width: 84,
      color: AppColors.sidebar,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      child: Column(children: [
        Tooltip(
          message: '$salonName\n${profile.roleLabel} · ${profile.fullName}',
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.sidebarMuted),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Text('LOGO', style: TextStyle(fontSize: 9, color: AppColors.sidebarMuted)),
          ),
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < _items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Tooltip(
              message: _items[i].label,
              child: Material(
                color: i == index ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelect(i),
                  child: SizedBox(
                    width: 64,
                    height: 58,
                    child: Stack(alignment: Alignment.center, children: [
                      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_items[i].icon, size: 22, color: Colors.white),
                        const SizedBox(height: 3),
                        Text(_items[i].short,
                            style: const TextStyle(fontSize: 10.5, color: AppColors.sidebarText)),
                      ]),
                      if (i == 1 && lowStock > 0)
                        Positioned(
                          top: 4,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: AppColors.badge, borderRadius: BorderRadius.circular(999)),
                            child: Text('$lowStock', style: const TextStyle(color: Colors.white, fontSize: 10)),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        Tooltip(
          message: printerName ?? 'Imprimante non choisie',
          child: Icon(Icons.print_outlined,
              color: printerName == null ? AppColors.badge : const Color(0xFF34D399)),
        ),
        const SizedBox(height: 12),
        IconButton(
          tooltip: 'Se déconnecter',
          onPressed: repo.signOut,
          icon: const Icon(Icons.logout, color: AppColors.sidebarMuted),
        ),
      ]),
    );
  }
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final int? badge;
  final VoidCallback onTap;

  const _NavButton({required this.item, required this.selected, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Icon(item.icon, size: 20, color: selected ? Colors.white : AppColors.sidebarText),
            const SizedBox(width: 12),
            Expanded(
              child: Text(item.label,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.sidebarText,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 15,
                  )),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppColors.badge, borderRadius: BorderRadius.circular(999)),
                child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
          ]),
        ),
      ),
    );
  }
}
