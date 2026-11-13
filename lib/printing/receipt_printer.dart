import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../util/money.dart';

/// Impression sur l'imprimante de tickets 58 mm.
/// L'imprimante est installée sous Windows avec son pilote ; on lui envoie
/// un document au format rouleau 57 mm. Le choix est mémorisé sur ce PC.
class ReceiptPrinter {
  static const _urlKey = 'receipt_printer_url';
  static const _nameKey = 'receipt_printer_name';

  static Future<List<Printer>> available() => Printing.listPrinters();

  static Future<String?> selectedName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nameKey);
  }

  static Future<String?> selectedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_urlKey);
  }

  static Future<void> select(Printer p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, p.url);
    await prefs.setString(_nameKey, p.name);
  }

  static Future<Printer> _printer() async {
    final url = await selectedUrl();
    final all = await available();
    if (url != null) {
      for (final p in all) {
        if (p.url == url) return p;
      }
    }
    throw Exception(
        "Imprimante de tickets introuvable. Choisissez-la dans Réglages > Imprimante.");
  }

  static Future<void> _send(pw.Document doc, String jobName) async {
    final printer = await _printer();
    final ok = await Printing.directPrintPdf(
      printer: printer,
      name: jobName,
      format: PdfPageFormat.roll57,
      onLayout: (_) async => doc.save(),
    );
    if (!ok) throw Exception("L'impression n'a pas abouti.");
  }

  // ---------------------------------------------------------------------

  /// Les polices PDF de base ne gèrent que l'alphabet latin : on remplace
  /// les autres caractères pour éviter un échec d'impression.
  static String _safe(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r == 0x2014 || r == 0x2013 || r == 0x2212) {
        b.write('-');
      } else if (r == 0x2019) {
        b.write("'");
      } else if (r < 0x20 && r != 0x0A) {
        continue;
      } else if (r > 0xFF) {
        b.write('?');
      } else {
        b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  static pw.Document _doc(List<pw.Widget> Function() build) {
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: pw.Font.courier(), bold: pw.Font.courierBold()),
    );
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll57.copyWith(
        marginLeft: 2 * PdfPageFormat.mm,
        marginRight: 2 * PdfPageFormat.mm,
        marginTop: 3 * PdfPageFormat.mm,
        marginBottom: 8 * PdfPageFormat.mm,
      ),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: build(),
      ),
    ));
    return doc;
  }

  static pw.Widget _t(String s, {bool bold = false, double size = 8, pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Text(_safe(s),
          textAlign: align,
          style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal));

  static pw.Widget _row(String left, String right, {bool bold = false, double size = 8}) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _t(left, bold: bold, size: size)),
          pw.SizedBox(width: 4),
          _t(right, bold: bold, size: size),
        ],
      );

  static pw.Widget _sep() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text('-' * 28, maxLines: 1, style: const pw.TextStyle(fontSize: 8)),
      );

  static List<pw.Widget> _header(SalonSettings s) => [
        _t(s.salonName, bold: true, size: 10, align: pw.TextAlign.center),
        if (s.address.isNotEmpty) _t(s.address, align: pw.TextAlign.center),
        if (s.phone.isNotEmpty) _t('Tél. ${s.phone}', align: pw.TextAlign.center),
        _sep(),
      ];

  static String _date(DateTime d) => DateFormat('dd/MM/yy HH:mm').format(d.toLocal());

  // ---------------------------------------------------------------------

  /// Reçu de la cliente. [sale] est la ligne renvoyée par create_sale.
  static Future<void> printSale({
    required SalonSettings settings,
    required Map<String, dynamic> sale,
    required List<CartLine> lines,
    required String cashierName,
    Customer? customer,
  }) async {
    final subtotal = asInt(sale['subtotal_cents']);
    final discount = asInt(sale['discount_cents']);
    final total = asInt(sale['total_cents']);
    final paid = asInt(sale['paid_cents']);
    final change = asInt(sale['change_cents']);
    final debtBefore = asInt(sale['debt_before_cents']);
    final settled = asInt(sale['debt_settled_cents']);
    final credit = asInt(sale['credit_cents']);
    final balanceAfter = debtBefore - settled + credit;
    final method = saleMethods[sale['payment_method']] ?? '${sale['payment_method']}';
    final createdAt = DateTime.tryParse('${sale['created_at']}') ?? DateTime.now();
    final ticketNo = '${sale['ticket_no']}'.padLeft(4, '0');

    final doc = _doc(() => [
          ..._header(settings),
          _row('Ticket $ticketNo', _date(createdAt)),
          if (customer != null) _t('Cliente : ${customer.fullName}'),
          _sep(),
          for (final l in lines) ...[
            _row(l.quantity > 1 ? '${l.quantity} x ${l.label}' : l.label, formatDa(l.totalCents, suffix: false)),
            if (l.employeeName != null) _t('  par ${l.employeeName}', size: 7),
          ],
          _sep(),
          _row('Sous-total', formatDa(subtotal, suffix: false)),
          if (discount > 0) _row('Remise fidélité', '-${formatDa(discount, suffix: false)}'),
          _row(settled > 0 ? 'Total du ticket' : 'TOTAL', formatDa(total),
              bold: settled == 0, size: settled > 0 ? 8 : 10),
          if (settled > 0) ...[
            _row('Ancien crédit', formatDa(settled, suffix: false)),
            _row('A PAYER', formatDa(total + settled), bold: true, size: 10),
          ],
          _row('Payé : $method', formatDa(paid, suffix: false)),
          if (change > 0) _row('Rendu', formatDa(change, suffix: false)),
          if (credit > 0) _row('Reste dû', formatDa(credit), bold: true),
          if (customer != null && balanceAfter > 0)
            _t('Crédit total de la cliente : ${formatDa(balanceAfter)}', bold: true),
          _sep(),
          if (customer != null) _t('Points fidélité : ${customer.loyaltyPoints}', align: pw.TextAlign.center),
          _t(settings.receiptFooter, bold: true, align: pw.TextAlign.center),
          _t('Encaissé par $cashierName', size: 7, align: pw.TextAlign.center),
        ]);
    await _send(doc, 'Ticket $ticketNo');
  }

  /// Reçu de paie remis à l'employée.
  static Future<void> printPayslip({
    required SalonSettings settings,
    required PayrollLine line,
    required Map<String, dynamic> payment,
    required DateTime month,
    required String paidBy,
  }) async {
    final bonus = asInt(payment['bonus_cents']);
    final total = asInt(payment['total_cents']);
    final paidAt = DateTime.tryParse('${payment['paid_at']}') ?? DateTime.now();
    final monthText = DateFormat('MMMM yyyy', 'fr_FR').format(month);
    final doc = _doc(() => [
          ..._header(settings),
          _t('REÇU DE SALAIRE', bold: true, size: 9, align: pw.TextAlign.center),
          _t(monthText, align: pw.TextAlign.center),
          _sep(),
          _t('Employée : ${line.fullName}', bold: true),
          _row('Salaire fixe', formatDa(asInt(payment['base_cents']), suffix: false)),
          _row('Commission ${formatQty(line.commissionPct)} %', formatDa(asInt(payment['commission_cents']), suffix: false)),
          if (bonus != 0) _row(bonus > 0 ? 'Prime' : 'Retenue', formatDa(bonus, suffix: false)),
          _row('TOTAL VERSÉ', formatDa(total), bold: true, size: 10),
          _sep(),
          _t('Payé le ${_date(paidAt)} par $paidBy'),
          pw.SizedBox(height: 18),
          _t('Signature employée :'),
          pw.SizedBox(height: 24),
        ]);
    await _send(doc, 'Salaire ${line.fullName}');
  }

  /// Bon de commande (produits manquants).
  /// [order] : produit et quantité à commander (en conditionnements).
  static Future<void> printOrder({
    required SalonSettings settings,
    required List<(Product, double)> order,
  }) async {
    final doc = _doc(() => [
          ..._header(settings),
          _t('BON DE COMMANDE', bold: true, size: 9, align: pw.TextAlign.center),
          _t(_date(DateTime.now()), align: pw.TextAlign.center),
          _sep(),
          for (final (p, qty) in order) ...[
            _row(p.name, '${formatQty(qty)} ${p.unit}'),
            if (p.hasContent) _t('  ${p.packagingLabel}', size: 7),
            _t('  en stock : ${p.stockLabel}', size: 7),
          ],
          _sep(),
        ]);
    await _send(doc, 'Bon de commande');
  }

  static Future<void> printTest(SalonSettings settings) async {
    final doc = _doc(() => [
          ..._header(settings),
          _t('Test d\'impression', bold: true, align: pw.TextAlign.center),
          _t(_date(DateTime.now()), align: pw.TextAlign.center),
          _row('Montant exemple', formatDa(123456)),
          _sep(),
        ]);
    await _send(doc, 'Test');
  }
}
