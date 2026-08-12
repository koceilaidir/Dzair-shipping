import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/dzair_logo.dart';

/// Coquille de l'app admin : navigation par onglets.
/// Chaque module sera branché au fil de la phase 2.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  static const _titles = ['Tableau de bord', 'Voyageurs', 'Missions', 'Créances', 'Réglages'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: DzColors.bg,
        titleSpacing: 16,
        title: Row(
          children: [
            const DzairLogo(size: 30),
            const SizedBox(width: 10),
            Text(_titles[_tab],
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
      body: _tab == 0 ? const _DashboardPlaceholder() : _ModulePlaceholder(title: _titles[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Tableau'),
          NavigationDestination(icon: Icon(Icons.group_outlined), label: 'Voyageurs'),
          NavigationDestination(icon: Icon(Icons.flight_takeoff_outlined), label: 'Missions'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Créances'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Réglages'),
        ],
      ),
    );
  }
}

class _DashboardPlaceholder extends StatelessWidget {
  const _DashboardPlaceholder();

  @override
  Widget build(BuildContext context) {
    final kpis = [
      ('DA sortis (mois)', '—', DzColors.txt),
      ('DA encaissés (mois)', '—', DzColors.txt),
      ('Net agence', '—', DzColors.lime),
      ('Créances dehors', '—', DzColors.amber),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Bienvenue 👋',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Les chiffres arriveront avec la connexion à l’API (phase 1).',
            style: TextStyle(color: DzColors.mut, fontSize: 13)),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 700 ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.7,
          children: [
            for (final (label, value, color) in kpis)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label.toUpperCase(),
                          style: const TextStyle(
                              color: DzColors.mut,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2)),
                      const Spacer(),
                      Text(value,
                          style: TextStyle(
                              color: color, fontSize: 24, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ModulePlaceholder extends StatelessWidget {
  final String title;
  const _ModulePlaceholder({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Opacity(opacity: .35, child: DzairLogo(size: 72)),
          const SizedBox(height: 14),
          Text('$title — en construction',
              style: const TextStyle(color: DzColors.mut, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
