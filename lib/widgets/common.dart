import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';

// =====================================================================
// Messages
// =====================================================================

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

// =====================================================================
// Mise en page responsive
// =====================================================================

/// Marges d'un écran selon la largeur disponible.
EdgeInsets screenPadding(double width) =>
    width < 760 ? const EdgeInsets.fromLTRB(16, 16, 16, 16) : const EdgeInsets.fromLTRB(32, 28, 32, 28);

/// Espace entre deux blocs selon la largeur.
double gapFor(double width) => width < 760 ? 12 : 20;

// =====================================================================
// Blocs de base
// =====================================================================

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
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: AppColors.ink)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(subtitle!, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
              ),
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
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    SectionTitle(title!),
                    if (trailing != null) trailing!,
                  ],
                ),
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
          Text(label, style: TextStyle(fontSize: 13, color: fg), maxLines: 1, overflow: TextOverflow.ellipsis),
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
            Text(sub!, style: TextStyle(fontSize: 12, color: fg), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

/// Cartes chiffres : 4 par ligne sur grand écran, 2 en moyen, 1 en petit.
class StatRow extends StatelessWidget {
  final List<Widget> children;
  const StatRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final perRow = c.maxWidth >= 1000 ? children.length : (c.maxWidth >= 520 ? 2 : 1);
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
/// Il prend la largeur de son texte ; placé dans un Expanded il remplit la place.
class ChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// true : pastille ronde, sélection en noir (catégories, filtres).
  /// false : bouton rectangulaire, sélection bordée de prune (paiement, catégories de dépense).
  final bool dark;
  final IconData? icon;

  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dark = true,
    this.icon,
  });

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
      bg = AppColors.accentSoft;
      fg = AppColors.accent;
      border = AppColors.accent;
    } else {
      bg = Colors.white;
      fg = AppColors.ink;
      border = AppColors.line;
    }
    final radius = BorderRadius.circular(dark ? 999 : 10);
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: border, width: selected && !dark ? 1.6 : 1),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: fg),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
                  ),
                ),
              ],
            ),
          ),
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
      child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Expanded(child: Text(label, style: s)),
        const SizedBox(width: 8),
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

// =====================================================================
// Boîtes de dialogue et menus au style du logiciel
// =====================================================================

/// Boîte de dialogue standard : fond blanc, coins arrondis, titre + croix,
/// contenu qui défile si besoin, boutons alignés à droite.
class AppDialog extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget content;
  final List<Widget> actions;
  final double width;

  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.subtitle,
    this.width = 480,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.line),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.ink)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                      ],
                    ]),
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.close, color: AppColors.muted),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: AppColors.lineSoft),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                child: content,
              ),
            ),
            const Divider(height: 1, color: AppColors.lineSoft),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton « Annuler » des boîtes de dialogue.
class CancelButton extends StatelessWidget {
  final String label;
  const CancelButton({super.key, this.label = 'Annuler'});

  @override
  Widget build(BuildContext context) =>
      OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(label));
}

/// Bouton principal avec indicateur de chargement.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false, this.icon});

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : Text(label);
    if (icon != null && !busy) {
      return FilledButton.icon(onPressed: onPressed, icon: Icon(icon), label: child);
    }
    return FilledButton(onPressed: busy ? null : onPressed, child: child);
  }
}

/// Menu déroulant au style du logiciel (menu blanc arrondi).
class AppDropdown<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String label;

  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      // `value` reste accepté par Flutter ; `initialValue` ne suit pas les changements d'état.
      // ignore: deprecated_member_use
      value: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 4,
      menuMaxHeight: 420,
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.muted),
      decoration: InputDecoration(labelText: label),
    );
  }
}

/// Choix d'une date (champ cliquable + calendrier).
class DateField extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final String label;
  const DateField({super.key, required this.value, required this.onChanged, this.label = 'Date'});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          helpText: 'Choisir la date',
          cancelText: 'Annuler',
          confirmText: 'Valider',
        );
        if (d != null) onChanged(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.event_outlined, color: AppColors.muted),
        ),
        child: Text(DateFormat('EEE d MMM yyyy', 'fr_FR').format(value)),
      ),
    );
  }
}

/// Champ quantité avec boutons − / + (pratique au tactile).
class QtyStepper extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final double step;
  final String Function(double) format;

  const QtyStepper({super.key, required this.value, required this.onChanged, required this.format, this.step = 1});

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
          tooltip: 'Moins',
          visualDensity: VisualDensity.compact,
          onPressed: value - step < 0 ? null : () => onChanged(value - step),
          icon: const Icon(Icons.remove, size: 18),
        ),
        SizedBox(
          width: 44,
          child: Text(format(value), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        IconButton(
          tooltip: 'Plus',
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(value + step),
          icon: const Icon(Icons.add, size: 18),
        ),
      ]),
    );
  }
}

Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'Confirmer'}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (c) => AppDialog(
      title: title,
      width: 440,
      content: Text(message, style: const TextStyle(fontSize: 15)),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return res ?? false;
}
