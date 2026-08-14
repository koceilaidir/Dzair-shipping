import 'package:flutter/material.dart';
import '../theme.dart';

String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String dateFr(dynamic iso) {
  if (iso == null) return '—';
  final s = '$iso';
  if (s.length < 10) return s;
  const mois = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  final m = int.tryParse(s.substring(5, 7)) ?? 1;
  return '${int.tryParse(s.substring(8, 10)) ?? ''} ${mois[m - 1]} ${s.substring(0, 4)}';
}

const _moisCourts = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin',
  'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc'];

/// Champ date : ouvre le sélecteur Dzair (année + mois + jour cliquables).
class DzDateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final int pastYears;
  final int futureYears;
  const DzDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.pastYears = 1,
    this.futureYears = 2,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final d = await showDzDatePicker(
          context,
          initial: value,
          pastYears: pastYears,
          futureYears: futureYears,
        );
        if (d != null) onChanged(d);
      },
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_month_outlined, color: DzColors.mut, size: 18),
        ),
        child: Text(
          value == null ? 'Choisir…' : dateFr(isoDate(value!)),
          style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: value == null ? DzColors.mut : DzColors.txt),
        ),
      ),
    );
  }
}

Future<DateTime?> showDzDatePicker(BuildContext context,
    {DateTime? initial, int pastYears = 1, int futureYears = 2}) {
  final now = DateTime.now();
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _DzPicker(
      initial: initial ?? now,
      minYear: now.year - pastYears,
      maxYear: now.year + futureYears,
    ),
  );
}

class _DzPicker extends StatefulWidget {
  final DateTime initial;
  final int minYear, maxYear;
  const _DzPicker({required this.initial, required this.minYear, required this.maxYear});

  @override
  State<_DzPicker> createState() => _DzPickerState();
}

class _DzPickerState extends State<_DzPicker> {
  late int _year = widget.initial.year;
  late int _month = widget.initial.month;
  late int _day = widget.initial.day;

  int get _daysInMonth => DateTime(_year, _month + 1, 0).day;

  @override
  Widget build(BuildContext context) {
    if (_day > _daysInMonth) _day = _daysInMonth;
    return Dialog(
      backgroundColor: DzColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Année : ‹ 2026 ›
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                onPressed: _year > widget.minYear ? () => setState(() => _year--) : null,
                icon: const Icon(Icons.chevron_left, color: DzColors.lime),
              ),
              Text('$_year',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              IconButton(
                onPressed: _year < widget.maxYear ? () => setState(() => _year++) : null,
                icon: const Icon(Icons.chevron_right, color: DzColors.lime),
              ),
            ]),
            const SizedBox(height: 8),
            // Mois : grille 4×3
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.1,
              children: [
                for (var m = 1; m <= 12; m++)
                  _chip(_moisCourts[m - 1], m == _month, () => setState(() => _month = m)),
              ],
            ),
            const Divider(color: DzColors.line, height: 24),
            // Jour : grille 7 colonnes
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.1,
              children: [
                for (var d = 1; d <= _daysInMonth; d++)
                  _chip('$d', d == _day, () => setState(() => _day = d)),
              ],
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annuler'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(
                  onPressed: () => Navigator.pop(context, DateTime(_year, _month, _day)),
                  child: const Text('Valider'))),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _chip(String txt, bool on, VoidCallback onTap) => Material(
        color: on ? DzColors.lime : DzColors.card2,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Center(
            child: Text(txt,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                    color: on ? DzColors.inkOnLime : DzColors.txt)),
          ),
        ),
      );
}
