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

/// Champ date commun : calendrier au clic, année en cours par défaut (cliquable).
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
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - pastYears),
          lastDate: DateTime(now.year + futureYears, 12, 31),
          helpText: label,
        );
        if (d != null) onChanged(d);
      },
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_month_outlined,
              color: DzColors.mut, size: 18),
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
