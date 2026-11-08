import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';

/// Message lisible à partir d'une erreur Supabase ou autre.
String errorMessage(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is AuthException) {
    if (e.message.toLowerCase().contains('invalid login')) {
      return 'E-mail ou mot de passe incorrect.';
    }
    return e.message;
  }
  if (e is StorageException) return 'Envoi du fichier impossible : ${e.message}';
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('ClientException')) {
    return 'Pas de connexion internet. Réessayez dans un instant.';
  }
  return s.replaceFirst('Exception: ', '');
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(errorMessage(e)),
    backgroundColor: AppColors.red,
  ));
}

void showInfo(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

String monthLabel(DateTime m) {
  final s = DateFormat('MMMM yyyy', 'fr_FR').format(m);
  return s[0].toUpperCase() + s.substring(1);
}

String dayLabel(DateTime d) {
  final s = DateFormat('EEEE d MMMM', 'fr_FR').format(d);
  return s[0].toUpperCase() + s.substring(1);
}

/// En-tête d'écran : titre + sous-titre + actions à droite.
class ScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const ScreenHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: AppColors.ink)),
            if (subtitle != null) ...[
              const SizedBox(width: 12),
              Text(subtitle!, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
            ],
          ],
        ),
        if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    );
  }
}

/// Carte blanche arrondie utilisée partout.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? title;
  final Widget? trailing;

  /// true quand le panneau a une hauteur imposée et que [child] doit la remplir
  /// (par exemple une liste qui défile).
  final bool expand;

  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.title,
    this.trailing,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: padding,
      child: title == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Row(children: [
                  SectionTitle(title!),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: trailing ?? const SizedBox.shrink(),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                if (expand) Expanded(child: child) else child,
              ],
            ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.ink));
}

enum Tone { neutral, green, orange, red }

Color toneFg(Tone t) => switch (t) {
      Tone.green => AppColors.green,
      Tone.orange => AppColors.orange,
      Tone.red => AppColors.red,
      Tone.neutral => AppColors.ink,
    };

Color toneBg(Tone t) => switch (t) {
      Tone.green => AppColors.greenBg,
      Tone.orange => AppColors.orangeBg,
      Tone.red => AppColors.redBg,
      Tone.neutral => Colors.white,
    };

Color toneLine(Tone t) => switch (t) {
      Tone.green => AppColors.greenLine,
      Tone.orange => AppColors.orangeLine,
      Tone.red => AppColors.redLine,
      Tone.neutral => AppColors.line,
    };

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Tone tone;

  const StatCard({super.key, required this.label, required this.value, this.sub, this.tone = Tone.neutral});

  @override
  Widget build(BuildContext context) {
    final fg = tone == Tone.neutral ? AppColors.muted : toneFg(tone);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: toneBg(tone),
        border: Border.all(color: toneLine(tone)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: fg)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: toneFg(tone),
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!, style: TextStyle(fontSize: 12, color: fg)),
          ],
        ],
      ),
    );
  }
}

/// Rangée de cartes chiffres qui passe à la ligne si la fenêtre est étroite.
class StatRow extends StatelessWidget {
  final List<Widget> children;
  const StatRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final perRow = c.maxWidth > 900 ? children.length : 2;
      final w = (c.maxWidth - 12 * (perRow - 1)) / perRow;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

class StatusBadge extends StatelessWidget {
  final String text;
  final Tone tone;
  const StatusBadge(this.text, {super.key, this.tone = Tone.neutral});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tone == Tone.neutral ? AppColors.bg : toneBg(tone),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: toneFg(tone))),
    );
  }
}

/// Sélecteur de mois ◀ Octobre 2026 ▶
class MonthSwitcher extends StatelessWidget {
  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  const MonthSwitcher({super.key, required this.month, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Mois précédent',
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
          icon: const Icon(Icons.chevron_left),
        ),
        SizedBox(
          width: 140,
          child: Text(monthLabel(month),
              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        IconButton(
          tooltip: 'Mois suivant',
          onPressed: () => onChanged(DateTime(month.year, month.month + 1)),
          icon: const Icon(Icons.chevron_right),
        ),
      ]),
    );
  }
}

/// Bouton-pastille sélectionnable (catégories, filtres, modes de paiement).
class ChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool dark;

  const ChoicePill({super.key, required this.label, required this.selected, required this.onTap, this.dark = true});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color border;
    if (selected && dark) {
      bg = AppColors.ink;
      fg = Colors.white;
      border = AppColors.ink;
    } else if (selected) {
      bg = Colors.white;
      fg = AppColors.accent;
      border = AppColors.accent;
    } else {
      bg = Colors.white;
      fg = AppColors.ink;
      border = AppColors.line;
    }
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(dark ? 999 : 10),
        side: BorderSide(color: border, width: selected && !dark ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(dark ? 999 : 10),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(color: fg, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
        ),
      ),
    );
  }
}

/// Ligne "libellé ........ valeur"
class KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? style;
  const KeyValueRow(this.label, this.value, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final s = style ?? const TextStyle(color: AppColors.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: s)),
        Text(value, style: s.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

/// Écran de chargement / erreur avec bouton "Réessayer".
class LoadState extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;
  const LoadState({super.key, this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (error == null) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off, size: 40, color: AppColors.muted),
        const SizedBox(height: 12),
        Text(errorMessage(error!), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
      ]),
    );
  }
}

Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'Confirmer'}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return res ?? false;
}
