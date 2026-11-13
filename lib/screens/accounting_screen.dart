import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../printing/receipt_printer.dart';
import '../theme.dart';
import '../util/money.dart';
import '../widgets/common.dart';

/// Écran 4 : comptabilité du mois, paie des employées, journal, clôture de caisse.
class AccountingScreen extends StatefulWidget {
  final Profile profile;
  const AccountingScreen({super.key, required this.profile});

  @override
  State<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends State<AccountingScreen> {
  DateTime _month = monthStart(DateTime.now());
  bool _loading = true;
  Object? _error;
  MonthSummary? _summary;
  List<PayrollLine> _payroll = [];
  List<LedgerEntry> _ledger = [];
  CashDay? _cash;

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
      final r = await Future.wait([
        repo.monthSummary(_month),
        repo.payroll(_month),
        repo.ledger(_month),
        repo.cashDay(DateTime.now()),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = r[0] as MonthSummary;
        _payroll = r[1] as List<PayrollLine>;
        _ledger = r[2] as List<LedgerEntry>;
        _cash = r[3] as CashDay;
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

  Future<void> _pay(PayrollLine line) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PayDialog(line: line, month: _month),
    );
    if (result == null || !mounted) return;
    showInfo(context, 'Salaire de ${line.fullName} enregistré : ${formatDa(asInt(result['total_cents']))}.');
    try {
      final s = await repo.settings();
      await ReceiptPrinter.printPayslip(
        settings: s,
        line: line,
        payment: result,
        month: _month,
        paidBy: widget.profile.fullName,
      );
    } catch (e) {
      if (mounted) showError(context, Exception('Reçu de paie non imprimé : ${errorMessage(e)}'));
    }
    _load();
  }

  Future<void> _closeDay() async {
    final cash = _cash;
    if (cash == null) return;
    final done = await showDialog<bool>(context: context, builder: (_) => _CloseDayDialog(cash: cash));
    if (done == true) _load();
  }

  Future<void> _exportCsv() async {
    try {
      final name = 'journal_${DateFormat('yyyy_MM').format(_month)}.csv';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer le journal',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (path == null) return;
      final b = StringBuffer('﻿Date;Libellé;Paiement;Entrée (DA);Sortie (DA)\r\n');
      for (final e in _ledger) {
        final label = e.label.replaceAll(';', ',');
        b.write('${DateFormat('dd/MM/yyyy HH:mm').format(e.at)};$label;${_methodLabel(e.paymentMethod)};'
            '${e.inCents == 0 ? '' : formatDa(e.inCents, suffix: false)};'
            '${e.outCents == 0 ? '' : formatDa(e.outCents, suffix: false)}\r\n');
      }
      final file = File(path.toLowerCase().endsWith('.csv') ? path : '$path.csv');
      await file.writeAsString(b.toString(), encoding: utf8);
      if (mounted) showInfo(context, 'Journal exporté : ${file.path}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  String _methodLabel(String m) => saleMethods[m] ?? expenseMethods[m] ?? m;

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 1150;
      final gap = gapFor(c.maxWidth);
      final header = ScreenHeader(
        title: 'Comptabilité & paie',
        actions: [
          MonthSwitcher(
            month: _month,
            onChanged: (m) {
              setState(() => _month = m);
              _load();
            },
          ),
          OutlinedButton.icon(
            onPressed: _ledger.isEmpty ? null : _exportCsv,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Exporter le journal (Excel)'),
          ),
        ],
      );
      if (s == null || _error != null) {
        return Padding(
          padding: screenPadding(c.maxWidth),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            header,
            Expanded(child: LoadState(error: _error, onRetry: _load)),
          ]),
        );
      }
      final stats = StatRow(children: [
        StatCard(label: 'Chiffre d\'affaires', value: formatDa(s.revenueCents), sub: '${s.tickets} tickets'),
        StatCard(
          label: 'Encaissé',
          value: formatDa(s.receivedCents),
          sub: s.creditOutstandingCents > 0
              ? 'Crédits clientes en cours : ${formatDa(s.creditOutstandingCents)}'
              : 'Aucun crédit client en cours',
          tone: s.creditOutstandingCents > 0 ? Tone.orange : Tone.neutral,
        ),
        StatCard(
          label: 'Dépenses + salaires',
          value: '- ${formatDa(s.expensesCents + s.salariesCents)}',
          sub: 'Dépenses ${formatDa(s.expensesCents, suffix: false)} · salaires ${formatDa(s.salariesCents, suffix: false)}',
        ),
        StatCard(
          label: s.netCents >= 0 ? 'Dans le vert' : 'Dans le rouge',
          value: formatDa(s.netCents),
          sub: 'Résultat net du mois',
          tone: s.netCents >= 0 ? Tone.green : Tone.red,
        ),
      ]);
      final progress = _loading ? const LinearProgressIndicator(minHeight: 2) : const SizedBox(height: 2);

      if (wide) {
        return Padding(
          padding: screenPadding(c.maxWidth),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            header,
            SizedBox(height: gap),
            stats,
            SizedBox(height: gap),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  width: 400,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: _payrollPanel(expand: true)),
                    SizedBox(height: gap),
                    _cashPanel(),
                  ]),
                ),
                SizedBox(width: gap),
                Expanded(child: _journalPanel(expand: true)),
              ]),
            ),
            progress,
          ]),
        );
      }
      return SingleChildScrollView(
        padding: screenPadding(c.maxWidth),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          SizedBox(height: gap),
          stats,
          progress,
          SizedBox(height: gap),
          _payrollPanel(expand: false),
          SizedBox(height: gap),
          _cashPanel(),
          SizedBox(height: gap),
          SizedBox(height: 520, child: _journalPanel(expand: true)),
        ]),
      );
    });
  }

  Widget _payrollPanel({required bool expand}) {
    return Panel(
      expand: expand,
      title: 'Paie des employées',
      child: _payroll.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                  child: Text('Aucune employée. Ajoutez-les dans Réglages.', style: TextStyle(color: AppColors.muted))),
            )
          : ListView.separated(
              shrinkWrap: !expand,
              physics: expand ? null : const NeverScrollableScrollPhysics(),
              itemCount: _payroll.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final l = _payroll[i];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.lineSoft),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    CircleAvatar(
                      backgroundColor: AppColors.accentSoft,
                      foregroundColor: AppColors.accent,
                      child: Text(l.fullName.isEmpty ? '?' : l.fullName[0].toUpperCase()),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          'Fixe ${formatDa(l.baseCents, suffix: false)} + commission ${formatDa(l.commissionCents, suffix: false)}'
                          '\n(${formatQty(l.commissionPct)} % de ${formatDa(l.servicesCents, suffix: false)})',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(formatDa(l.paid ? (l.paidTotalCents ?? l.dueCents) : l.dueCents),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      if (l.paid)
                        const StatusBadge('Payée', tone: Tone.green)
                      else if (widget.profile.mayPaySalaries)
                        FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(44, 36)),
                          onPressed: () => _pay(l),
                          child: const Text('Payer'),
                        )
                      else
                        const StatusBadge('À payer', tone: Tone.orange),
                    ]),
                  ]),
                );
              },
            ),
    );
  }

  Widget _cashPanel() {
    final c = _cash;
    if (c == null) return const SizedBox.shrink();
    return Panel(
      title: 'Caisse du jour',
      trailing: c.closed
          ? const StatusBadge('Clôturée', tone: Tone.green)
          : FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(44, 36)),
              onPressed: _closeDay,
              child: const Text('Clôturer la journée'),
            ),
      child: Column(children: [
        KeyValueRow('Fond de caisse (dernier comptage)', formatDa(c.openingCents)),
        KeyValueRow('+ Espèces encaissées (ventes, remboursements)', formatDa(c.salesCashCents)),
        KeyValueRow('- Dépenses en espèces', formatDa(c.expensesCashCents)),
        KeyValueRow('- Salaires en espèces', formatDa(c.salariesCashCents)),
        const Divider(),
        KeyValueRow('Attendu dans la caisse', formatDa(c.expectedCents),
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
        if (c.closed && c.countedCents != null) ...[
          KeyValueRow('Compté', formatDa(c.countedCents!)),
          KeyValueRow(
            'Écart',
            formatDa(c.countedCents! - c.expectedCents),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: c.countedCents! == c.expectedCents ? AppColors.green : AppColors.red,
            ),
          ),
        ],
      ]),
    );
  }

  Widget _journalPanel({required bool expand}) {
    const head = TextStyle(fontSize: 12, color: AppColors.muted);
    return Panel(
      expand: expand,
      title: 'Journal du mois',
      child: LayoutBuilder(builder: (context, c) {
        // Colonnes qui s'adaptent : on masque les moins utiles quand la place manque.
        final showMethod = c.maxWidth >= 640;
        final showRunning = c.maxWidth >= 520;
        final money = c.maxWidth >= 720 ? 120.0 : 100.0;

        Widget line({required Widget date, required Widget label, Widget? method, required Widget inW, required Widget outW, Widget? run}) {
          return Row(children: [
            SizedBox(width: 82, child: date),
            Expanded(child: label),
            if (showMethod) SizedBox(width: 92, child: method ?? const SizedBox()),
            SizedBox(width: money, child: inW),
            SizedBox(width: money, child: outW),
            if (showRunning) SizedBox(width: money + 10, child: run ?? const SizedBox()),
          ]);
        }

        var running = 0;
        final rows = <Widget>[];
        for (final e in _ledger) {
          running += e.inCents - e.outCents;
          rows.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            child: line(
              date: Text(DateFormat('dd/MM HH:mm').format(e.at), style: const TextStyle(fontSize: 13)),
              label: Text(e.label, overflow: TextOverflow.ellipsis, maxLines: 2),
              method: Text(_methodLabel(e.paymentMethod), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              inW: Text(e.inCents == 0 ? '' : formatDa(e.inCents, suffix: false),
                  textAlign: TextAlign.right, style: const TextStyle(color: AppColors.green)),
              outW: Text(e.outCents == 0 ? '' : formatDa(e.outCents, suffix: false),
                  textAlign: TextAlign.right, style: const TextStyle(color: AppColors.red)),
              run: Text(formatDa(running, suffix: false),
                  textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ));
        }

        return Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: line(
              date: const Text('Date', style: head),
              label: const Text('Libellé', style: head),
              method: const Text('Paiement', style: head),
              inW: const Text('Entrée', style: head, textAlign: TextAlign.right),
              outW: const Text('Sortie', style: head, textAlign: TextAlign.right),
              run: const Text('Cumul', style: head, textAlign: TextAlign.right),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('Aucune opération ce mois-ci.', style: TextStyle(color: AppColors.muted)))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => rows[i],
                  ),
          ),
        ]);
      }),
    );
  }
}

// ---------------------------------------------------------------------------

class _PayDialog extends StatefulWidget {
  final PayrollLine line;
  final DateTime month;
  const _PayDialog({required this.line, required this.month});

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  final _bonus = TextEditingController();
  bool _deduction = false;
  String _method = 'cash';
  bool _busy = false;

  @override
  void dispose() {
    _bonus.dispose();
    super.dispose();
  }

  int? get _bonusCents {
    if (_bonus.text.trim().isEmpty) return 0;
    final v = parseDa(_bonus.text);
    if (v == null) return null;
    return _deduction ? -v : v;
  }

  Future<void> _save() async {
    final bonus = _bonusCents;
    if (bonus == null) {
      showError(context, Exception('Montant de prime / retenue invalide.'));
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await repo.payEmployee(
        employeeId: widget.line.employeeId,
        month: widget.month,
        bonusCents: bonus,
        method: _method,
      );
      if (mounted) Navigator.pop(context, res);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.line;
    final bonus = _bonusCents ?? 0;
    return AppDialog(
      title: 'Payer ${l.fullName}',
      subtitle: monthLabel(widget.month),
      width: 480,
      content: Column(mainAxisSize: MainAxisSize.min, children: [
          KeyValueRow('Salaire fixe', formatDa(l.baseCents)),
          KeyValueRow('Commission (${formatQty(l.commissionPct)} %)', formatDa(l.commissionCents)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _bonus,
                decoration: InputDecoration(labelText: _deduction ? 'Retenue (avance…)' : 'Prime', suffixText: 'DA'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            ChoicePill(label: 'Prime', dark: false, selected: !_deduction, onTap: () => setState(() => _deduction = false)),
            const SizedBox(width: 6),
            ChoicePill(label: 'Retenue', dark: false, selected: _deduction, onTap: () => setState(() => _deduction = true)),
          ]),
          const SizedBox(height: 12),
          AppDropdown<String>(
            value: _method,
            label: 'Payé en',
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Espèces (sort de la caisse)')),
              DropdownMenuItem(value: 'transfer', child: Text('Virement')),
            ],
            onChanged: (v) => setState(() => _method = v ?? 'cash'),
          ),
          const Divider(height: 28),
          KeyValueRow('Total à verser', formatDa(l.dueCents + bonus),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
        ]),
      actions: [
        const CancelButton(),
        PrimaryButton(label: 'Payer et imprimer le reçu', busy: _busy, onPressed: _save),
      ],
    );
  }
}

class _CloseDayDialog extends StatefulWidget {
  final CashDay cash;
  const _CloseDayDialog({required this.cash});

  @override
  State<_CloseDayDialog> createState() => _CloseDayDialogState();
}

class _CloseDayDialogState extends State<_CloseDayDialog> {
  final _counted = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _counted.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = parseDa(_counted.text);
    if (v == null) {
      showError(context, Exception('Saisissez le montant compté dans la caisse.'));
      return;
    }
    setState(() => _busy = true);
    try {
      await repo.closeDay(DateTime.now(), v, _note.text.trim());
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
    final counted = parseDa(_counted.text);
    final diff = counted == null ? null : counted - widget.cash.expectedCents;
    return AppDialog(
      title: 'Clôturer la journée',
      subtitle: 'Comptez les espèces de la caisse.',
      width: 440,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KeyValueRow('Attendu dans la caisse', formatDa(widget.cash.expectedCents),
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 12),
          TextField(
            controller: _counted,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Montant compté', suffixText: 'DA'),
            onChanged: (_) => setState(() {}),
          ),
          if (diff != null) ...[
            const SizedBox(height: 8),
            Text(
              diff == 0 ? 'Caisse juste au centime.' : 'Écart : ${formatDa(diff)}',
              style: TextStyle(fontWeight: FontWeight.w600, color: diff == 0 ? AppColors.green : AppColors.red),
            ),
          ],
          const SizedBox(height: 12),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Commentaire (facultatif)')),
          const SizedBox(height: 8),
          const Text('Le propriétaire verra la clôture et l\'écart éventuel.',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      actions: [
        const CancelButton(),
        PrimaryButton(label: 'Clôturer', busy: _busy, onPressed: _save),
      ],
    );
  }
}
