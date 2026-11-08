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
  const _NavItem(this.icon, this.label);
}

const _items = [
  _NavItem(Icons.point_of_sale_outlined, 'Caisse'),
  _NavItem(Icons.inventory_2_outlined, 'Stock'),
  _NavItem(Icons.receipt_long_outlined, 'Dépenses & factures'),
  _NavItem(Icons.bar_chart_outlined, 'Comptabilité & paie'),
  _NavItem(Icons.settings_outlined, 'Réglages'),
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
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(
            index: _index,
            onSelect: _go,
            lowStock: _lowStock,
            salonName: _salonName,
            profile: widget.profile,
            printerName: _printerName,
          ),
          Expanded(
            child: KeyedSubtree(key: ValueKey(_index), child: _screen()),
          ),
        ],
      ),
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

  const _Sidebar({
    required this.index,
    required this.onSelect,
    required this.lowStock,
    required this.salonName,
    required this.profile,
    required this.printerName,
  });

  @override
  Widget build(BuildContext context) {
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
