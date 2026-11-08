// Tous les montants de l'application sont des entiers en CENTIMES.
// 1 500,00 DA = 150000. Aucun double n'est utilisé pour l'argent.

/// 150000 -> "1 500,00 DA"
String formatDa(int cents, {bool suffix = true}) {
  final negative = cents < 0;
  final abs = cents.abs();
  final units = (abs ~/ 100).toString();
  final decimals = (abs % 100).toString().padLeft(2, '0');
  final grouped = StringBuffer();
  for (var i = 0; i < units.length; i++) {
    if (i > 0 && (units.length - i) % 3 == 0) grouped.write(' ');
    grouped.write(units[i]);
  }
  return '${negative ? '-' : ''}$grouped,$decimals${suffix ? ' DA' : ''}';
}

/// "14 320,00" / "14320.5" / "14320" -> centimes. Retourne null si invalide.
int? parseDa(String input) {
  var t = input
      .trim()
      .replaceAll(RegExp(r'[\s  ]'), '')
      .replaceAll(RegExp(r'DA$', caseSensitive: false), '')
      .replaceAll(',', '.');
  if (t.isEmpty) return null;
  final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(t);
  if (m == null) return null;
  final units = int.parse(m.group(1)!);
  final decimals = int.parse((m.group(2) ?? '').padRight(2, '0'));
  return units * 100 + decimals;
}

/// Montant en centimes -> texte éditable "14320,00"
String centsToInput(int cents) => formatDa(cents, suffix: false).replaceAll(' ', '');

/// Quantité de stock : 3.5 -> "3,5", 4.0 -> "4"
String formatQty(double q) {
  if (q == q.roundToDouble()) return q.toStringAsFixed(0);
  var s = q.toStringAsFixed(3);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s.replaceAll('.', ',');
}

double? parseQty(String input) {
  final t = input.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

/// Convertit une valeur JSON (int, double ou texte) en entier.
int asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

double asDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}
