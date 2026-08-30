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
            titleSpacing: 0,
            leading: Builder(
              builder: (ctx) => IconButton(
                tooltip: 'Menu',
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                icon: const Icon(Icons.menu_rounded, color: DzColors.txt, size: 24),
              ),
            ),
            title: Row(children: [
              const DzairLogo(size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_items[_tab].$2,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ]),
            actions: [
              IconButton(
                tooltip: 'Messages',
                onPressed: () => setState(() => _tab = _tabMessages),
                icon: _avecBadge(
                    const Icon(Icons.chat_bubble_outline, color: DzColors.mut, size: 20)),
              ),
              IconButton(
                tooltip: 'Notifications',
                onPressed: () => setState(() => _tab = 0),
                icon: const Icon(Icons.notifications_none, color: DzColors.mut, size: 22),
              ),
              const SizedBox(width: 4),
            ],
          ),
          drawer: Drawer(
            width: 300,
            backgroundColor: const Color(0xFF111113),
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(right: Radius.circular(22))),
            child: SafeArea(
              child: Builder(
                builder: (ctx) => _SideNav(
                  tab: _tab,
                  items: _items,
                  nonLus: _nonLus,
                  tabMessages: _tabMessages,
                  largeur: double.infinity,
                  fond: Colors.transparent,
                  onClose: () => Navigator.pop(ctx),
                  onTap: (i) {
                    Navigator.pop(ctx);
                    setState(() => _tab = i);
                  },
                ),
              ),
            ),
          ),
          body: _content,
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
  final double largeur;
  final Color fond;
  final VoidCallback? onClose;
  const _SideNav({required this.tab, required this.items, required this.nonLus,
      required this.tabMessages, required this.onTap,
      this.largeur = 220, this.fond = DzColors.panel, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: largeur,
      color: fond,
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
            if (onClose != null)
              IconButton(
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, color: DzColors.mut, size: 19),
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
