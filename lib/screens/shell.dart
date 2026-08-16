import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/dzair_logo.dart';
import 'activite_screen.dart';
import 'chambres_screen.dart';
import 'dashboard_screen.dart';
import 'finance_screen.dart';
import 'inventaire_screen.dart';
import 'missions_screen.dart';
import 'reglages_screen.dart';
import 'voyageurs_screen.dart';

/// Coquille de l'app admin — navigation adaptative :
/// sidebar à gauche sur PC/tablette (comme la maquette), barre en bas sur téléphone.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  static const _items = [
    (Icons.dashboard_outlined, 'Tableau de bord'),
    (Icons.flight_takeoff_outlined, 'Missions'),
    (Icons.group_outlined, 'Voyageurs'),
    (Icons.inventory_2_outlined, 'Inventaire'),
    (Icons.storefront_outlined, 'Chambres'),
    (Icons.account_balance_wallet_outlined, 'Créances'),
    (Icons.bar_chart_outlined, 'Finance'),
    (Icons.history, 'Activité'),
    (Icons.settings_outlined, 'Réglages'),
  ];

  Widget get _content => switch (_tab) {
        0 => const DashboardScreen(),
        1 => const MissionsScreen(),
        2 => const VoyageursScreen(),
        3 => const InventaireScreen(),
        4 => const ChambresScreen(),
        6 => const FinanceScreen(),
        7 => const ActiviteScreen(),
        8 => const ReglagesScreen(),
        _ => _ModulePlaceholder(title: _items[_tab].$2),
      };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 950;

      if (!wide) {
        // ---- Téléphone : barre en bas ----
        return Scaffold(
          appBar: AppBar(
            backgroundColor: DzColors.bg,
            titleSpacing: 16,
            title: Row(children: [
              const DzairLogo(size: 30),
              const SizedBox(width: 10),
              Text(_items[_tab].$2,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ]),
          ),
          body: _content,
          // 5 onglets principaux + « Plus » (les autres modules dans une feuille).
          bottomNavigationBar: Builder(builder: (context) {
            const principaux = [0, 1, 2, 3, 4];
            final sel = principaux.indexOf(_tab);
            return NavigationBar(
              selectedIndex: sel < 0 ? 5 : sel,
              onDestinationSelected: (i) async {
                if (i < principaux.length) { setState(() => _tab = principaux[i]); return; }
                final choix = await showModalBottomSheet<int>(
                  context: context,
                  backgroundColor: DzColors.card,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(height: 10),
                    for (var k = 0; k < _items.length; k++)
                      if (!principaux.contains(k))
                        ListTile(
                          leading: Icon(_items[k].$1, color: k == _tab ? DzColors.lime : DzColors.mut),
                          title: Text(_items[k].$2),
                          onTap: () => Navigator.pop(context, k),
                        ),
                    const SizedBox(height: 8),
                  ])),
                );
                if (choix != null) setState(() => _tab = choix);
              },
              destinations: [
                for (final k in principaux)
                  NavigationDestination(icon: Icon(_items[k].$1), label: _items[k].$2.split(' ').first),
                const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Plus'),
              ],
            );
          }),
        );
      }

      // ---- PC / tablette : sidebar à gauche ----
      return Scaffold(
        body: Row(children: [
          _SideNav(
            tab: _tab,
            items: _items,
            onTap: (i) => setState(() => _tab = i),
          ),
          Container(width: 1, color: DzColors.line),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(children: [
                  Text('Dzair Shipping  /  ',
                      style: const TextStyle(color: DzColors.mut, fontSize: 12)),
                  Text(_items[_tab].$2,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  const Icon(Icons.notifications_none, color: DzColors.mut, size: 19),
                ]),
              ),
              Expanded(child: _content),
            ]),
          ),
        ]),
      );
    });
  }
}

class _SideNav extends StatelessWidget {
  final int tab;
  final List<(IconData, String)> items;
  final ValueChanged<int> onTap;
  const _SideNav({required this.tab, required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: DzColors.panel,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Profil
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 18),
          child: Row(children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: DzColors.lime,
              child: Text((Api.nom ?? 'A').characters.first.toUpperCase(),
                  style: const TextStyle(
                      color: DzColors.inkOnLime, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Api.nom ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                Text(Api.role == 'admin' ? 'Administrateur' : (Api.role ?? ''),
                    style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
              ]),
            ),
          ]),
        ),
        // Recherche
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          height: 36,
          decoration: BoxDecoration(
            color: DzColors.card2,
            border: Border.all(color: DzColors.line),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Row(children: [
            Icon(Icons.search, size: 15, color: DzColors.mut),
            SizedBox(width: 8),
            Expanded(
              child: TextField(
                style: TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  hintText: 'Rechercher…',
                  hintStyle: TextStyle(color: DzColors.mut, fontSize: 12.5),
                ),
              ),
            ),
          ]),
        ),
        // Navigation
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: i == tab ? DzColors.lime : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Icon(items[i].$1, size: 17,
                        color: i == tab ? DzColors.inkOnLime : DzColors.mut),
                    const SizedBox(width: 10),
                    Text(items[i].$2,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: i == tab ? FontWeight.w700 : FontWeight.w500,
                          color: i == tab ? DzColors.inkOnLime : DzColors.mut,
                        )),
                  ]),
                ),
              ),
            ),
          ),
        const Spacer(),
        // Logo bas de sidebar
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(children: [
            const DzairLogo(size: 34),
            const SizedBox(width: 10),
            RichText(
              text: const TextSpan(
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                    color: DzColors.txt),
                children: [
                  TextSpan(text: 'Dzair '),
                  TextSpan(text: 'Shipping', style: TextStyle(color: DzColors.lime)),
                ],
              ),
            ),
          ]),
        ),
      ]),
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
