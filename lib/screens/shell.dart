import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/dzair_logo.dart';
import 'activite_screen.dart';
import 'chambres_screen.dart';
import 'creances_screen.dart';
import 'dashboard_screen.dart';
import 'finance_screen.dart';
import 'inventaire_screen.dart';
import 'messages_screen.dart';
import 'missions_screen.dart';
import 'reglages_screen.dart';
import 'voyageurs_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  int _nonLus = 0;
  Timer? _timerNonLus;

  static const _tabMessages = 8;

  static const _items = [
    (Icons.dashboard_outlined, 'Tableau de bord'),
    (Icons.flight_takeoff_outlined, 'Missions'),
    (Icons.group_outlined, 'Voyageurs'),
    (Icons.inventory_2_outlined, 'Inventaire'),
    (Icons.storefront_outlined, 'Chambres'),
    (Icons.account_balance_wallet_outlined, 'Créances'),
    (Icons.bar_chart_outlined, 'Finance'),
    (Icons.history, 'Activité'),
    (Icons.chat_bubble_outline, 'Messages'),
    (Icons.settings_outlined, 'Réglages'),
  ];

  @override
  void initState() {
    super.initState();
    _majNonLus();
    _timerNonLus = Timer.periodic(const Duration(seconds: 30), (_) => _majNonLus());
  }

  @override
  void dispose() {
    _timerNonLus?.cancel();
    super.dispose();
  }

  Future<void> _majNonLus() async {
    try {
      final d = await Api.get('/messages/non-lus') as Map;
      final n = (num.tryParse('${d['total']}') ?? 0).toInt();
      if (mounted && n != _nonLus) setState(() => _nonLus = n);
    } catch (_) {}
  }

  Widget get _content => switch (_tab) {
        0 => DashboardScreen(
            onOuvrirMessages: () => setState(() => _tab = _tabMessages)),
        1 => const MissionsScreen(),
        2 => const VoyageursScreen(),
        3 => const InventaireScreen(),
        4 => const ChambresScreen(),
        5 => const CreancesScreen(),
        6 => const FinanceScreen(),
        7 => const ActiviteScreen(),
        8 => MessagesScreen(onLu: _majNonLus),
        9 => const ReglagesScreen(),
        _ => _ModulePlaceholder(title: _items[_tab].$2),
      };

  Widget _avecBadge(Widget icone, {double topOffset = -4, double rightOffset = -6}) {
    if (_nonLus <= 0) return icone;
    return Stack(clipBehavior: Clip.none, children: [
      icone,
      Positioned(
        top: topOffset, right: rightOffset,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
          constraints: const BoxConstraints(minWidth: 15),
          decoration: BoxDecoration(
            color: DzColors.lime,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(_nonLus > 99 ? '99+' : '$_nonLus',
              textAlign: TextAlign.center,
              style: const TextStyle(color: DzColors.inkOnLime, fontSize: 8.5,
                  fontWeight: FontWeight.w800, height: 1.2)),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 950;

      if (!wide) {

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
            actions: [
              IconButton(
                tooltip: 'Messages',
                onPressed: () => setState(() => _tab = _tabMessages),
                icon: _avecBadge(
                    const Icon(Icons.notifications_none, color: DzColors.mut, size: 21)),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: _content,

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
                          trailing: k == _tabMessages && _nonLus > 0
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: DzColors.lime,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text('$_nonLus',
                                      style: const TextStyle(color: DzColors.inkOnLime,
                                          fontSize: 10.5, fontWeight: FontWeight.w800)),
                                )
                              : null,
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
                NavigationDestination(
                    icon: _avecBadge(const Icon(Icons.more_horiz)), label: 'Plus'),
              ],
            );
          }),
        );
      }

      return Scaffold(
        body: Row(children: [
          _SideNav(
            tab: _tab,
            items: _items,
            nonLus: _nonLus,
            tabMessages: _tabMessages,
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

                  InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: () => setState(() => _tab = _tabMessages),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: _avecBadge(
                          const Icon(Icons.notifications_none, color: DzColors.mut, size: 19)),
                    ),
                  ),
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
  final int nonLus;
  final int tabMessages;
  final ValueChanged<int> onTap;
  const _SideNav({required this.tab, required this.items, required this.nonLus,
      required this.tabMessages, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: DzColors.panel,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 18),
          child: Row(children: [
            Container(
              width: 34, height: 34, alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: DzColors.card2,
                shape: BoxShape.circle,
              ),
              child: Text((Api.nom ?? 'A').characters.first.toUpperCase(),
                  style: const TextStyle(
                      color: DzColors.lime, fontWeight: FontWeight.w800, fontSize: 14)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Api.nom ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                Text(Api.role == 'admin' ? 'Administrateur'
                        : Api.role == 'voyageur' ? 'Voyageur' : (Api.role ?? ''),
                    style: const TextStyle(color: DzColors.mut, fontSize: 10.5)),
              ]),
            ),
          ]),
        ),

        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          height: 36,
          decoration: BoxDecoration(
            color: DzColors.card2,
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

        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Material(
              color: i == tab ? DzColors.card : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                  child: Row(children: [
                    Icon(items[i].$1, size: 17,
                        color: i == tab ? DzColors.lime : DzColors.mut),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(items[i].$2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: i == tab ? FontWeight.w600 : FontWeight.w500,
                            color: i == tab ? DzColors.txt : DzColors.mut,
                          )),
                    ),
                    if (i == tabMessages && nonLus > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2),
                        decoration: BoxDecoration(
                          color: DzColors.lime,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(nonLus > 99 ? '99+' : '$nonLus',
                            style: const TextStyle(color: DzColors.inkOnLime,
                                fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        const Spacer(),

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
