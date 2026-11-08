import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../data/repo.dart';
import '../theme.dart';
import '../util/money.dart';
import '../widgets/common.dart';

/// Écran 3 : dépenses et factures (électricité, eau, loyer, fournisseurs…).
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  DateTime _month = monthStart(DateTime.now());
  bool _loading = true;
  Object? _error;
  List<Expense> _expenses = [];

  // Formulaire
  String _category = 'electricite';
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  String _method = 'cash';
  String? _filePath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await repo.expenses(_month);
      if (!mounted) return;
      setState(() {
        _expenses = list;
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

  Future<String?> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Photo ou scan de la facture',
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    return res?.files.single.path;
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    final cents = parseDa(_amount.text);
    if (cents == null || cents <= 0) {
      showError(context, Exception('Montant invalide. Exemple : 14 320,00'));
      return;
    }
    setState(() => _saving = true);
    try {
      await repo.addExpense(
        category: _category,
        amountCents: cents,
        date: _date,
        paymentMethod: _method,
        note: _note.text.trim(),
        localReceiptPath: _filePath,
      );
      if (!mounted) return;
      showInfo(context, 'Dépense de ${formatDa(cents)} enregistrée.');
      setState(() {
        _amount.clear();
        _note.clear();
        _filePath = null;
        _month = monthStart(_date);
      });
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openReceipt(Expense e) async {
    try {
      if (e.receiptPath == null) {
        final path = await _pickFile();
        if (path == null) return;
        await repo.attachReceipt(e, path);
        if (mounted) showInfo(context, 'Facture jointe.');
        _load();
        return;
      }
      final url = await repo.receiptUrl(e.receiptPath!);
      await launchUrl(Uri.parse(url));
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: 'Dépenses & factures',
            actions: [MonthSwitcher(month: _month, onChanged: (m) {
              setState(() => _month = m);
              _load();
            })],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 380, child: SingleChildScrollView(child: _form())),
                const SizedBox(width: 20),
                Expanded(
                  child: _loading && _expenses.isEmpty || _error != null
                      ? LoadState(error: _error, onRetry: _load)
                      : _right(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _form() {
    return Panel(
      title: 'Nouvelle dépense',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Catégorie', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.6,
            children: [
              for (final e in expenseCategories.entries)
                ChoicePill(
                  label: e.value,
                  dark: false,
                  selected: _category == e.key,
                  onTap: () => setState(() => _category = e.key),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amount,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(labelText: 'Montant (au centime)', suffixText: 'DA', hintText: '14 320,00'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(DateFormat('dd/MM/yyyy').format(_date)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _method,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Payé en'),
                items: [
                  for (final e in expenseMethods.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _method = v ?? 'cash'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (ex. Sonelgaz 3e trimestre)')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: AppColors.bg),
            onPressed: () async {
              final p = await _pickFile();
              if (p != null) setState(() => _filePath = p);
            },
            icon: Icon(_filePath == null ? Icons.photo_camera_outlined : Icons.check_circle_outline,
                color: _filePath == null ? AppColors.muted : AppColors.green),
            label: Text(
              _filePath == null ? 'Joindre la photo de la facture' : 'Facture jointe : ${_filePath!.split(RegExp(r'[\\/]')).last}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Enregistrer la dépense'),
          ),
        ],
      ),
    );
  }

  Widget _right() {
    final total = _expenses.fold<int>(0, (a, e) => a + e.amountCents);
    final byCat = <String, int>{};
    for (final e in _expenses) {
      byCat[e.category] = (byCat[e.category] ?? 0) + e.amountCents;
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxCat = cats.isEmpty ? 1 : cats.first.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          title: 'Total du mois',
          trailing: Text(formatDa(total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          child: cats.isEmpty
              ? const Text('Aucune dépense ce mois-ci.', style: TextStyle(color: AppColors.muted))
              : Column(children: [
                  for (final c in cats)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        SizedBox(width: 120, child: Text(expenseCategories[c.key] ?? c.key)),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: c.value / maxCat,
                              minHeight: 12,
                              backgroundColor: AppColors.lineSoft,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        SizedBox(width: 130, child: Text(formatDa(c.value), textAlign: TextAlign.right)),
                      ]),
                    ),
                ]),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Panel(
            expand: true,
            title: 'Saisies du mois',
            child: _expenses.isEmpty
                ? const Center(child: Text('Rien pour ce mois.', style: TextStyle(color: AppColors.muted)))
                : ListView.separated(
                    itemCount: _expenses.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = _expenses[i];
                      final hasFile = e.receiptPath != null;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          SizedBox(width: 56, child: Text(DateFormat('dd/MM').format(e.date))),
                          SizedBox(width: 120, child: Text(e.categoryLabel)),
                          Expanded(
                            child: Text(
                              '${e.note}${e.note.isEmpty ? '' : ' · '}${expenseMethods[e.paymentMethod] ?? ''}',
                              style: const TextStyle(color: AppColors.muted),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _openReceipt(e),
                            icon: Icon(hasFile ? Icons.attach_file : Icons.warning_amber_rounded,
                                size: 18, color: hasFile ? AppColors.green : AppColors.orange),
                            label: Text(hasFile ? 'Voir la facture' : 'Facture manquante',
                                style: TextStyle(color: hasFile ? AppColors.green : AppColors.orange)),
                          ),
                          SizedBox(
                            width: 130,
                            child: Text(formatDa(e.amountCents),
                                textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
