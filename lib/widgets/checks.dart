typedef DzCheck = (String, String, bool);

const kChecksDepart = <DzCheck>[
  ('passeport', 'Passeport valide en poche', false),
  ('autorisations', 'Autorisations ANAE imprimées', true),
  ('carte_ae', 'Carte auto-entrepreneur', true),
  ('argent_depose', 'Argent déposé dans les cartes', true),
  ('enveloppe_douane', 'Enveloppe douane préparée (DA en liquide)', true),
  ('sim', 'Puce SIM emportée', false),
  ('vpn', 'VPN installé', false),
  ('wechat_alipay', 'WeChat + Alipay authentifiés', false),
  ('nourriture', 'Nourriture (5 jours)', false),
];

const kChecksRetour = <DzCheck>[
  ('factures_dl', 'Factures téléchargées (PDF)', true),
  ('factures_cachet', 'Factures imprimées et cachetées', true),
  ('factures_scan', 'Factures scannées', true),
  ('factures_anae', 'Factures chargées sur le site ANAE', true),
  ('qr_colles', 'Codes QR imprimés et collés sur les valises', true),
];

List<DzCheck> checksPour(List<DzCheck> items, bool nonDeclare) =>
    nonDeclare ? items.where((i) => !i.$3).toList() : items;

double _n(dynamic v) => v == null ? 0 : (num.tryParse('$v') ?? 0).toDouble();

Map<String, bool> autoDepartDe(Map m, {required bool nonDeclare, double marchandiseDA = 0}) => {
      'billet_ok': _n(m['billet']) > 0 && m['depart'] != null,
      if (!nonDeclare) 'argent_depose': marchandiseDA > 0,
    };

(int, int) avancementCheck(
  Map m,
  String champ, {
  required bool nonDeclare,
  double marchandiseDA = 0,
}) {
  final depart = champ == 'check_depart';
  final items = checksPour(depart ? kChecksDepart : kChecksRetour, nonDeclare);
  final auto = depart
      ? autoDepartDe(m, nonDeclare: nonDeclare, marchandiseDA: marchandiseDA)
      : const <String, bool>{};
  final etat = Map<String, dynamic>.from(m[champ] as Map? ?? {});
  bool val(String cle) => etat[cle] == true || auto[cle] == true;

  final total = items.length + (depart ? 1 : 0);
  var faits = items.where((i) => val(i.$1)).length;
  if (depart && (auto['billet_ok'] ?? false)) faits += 1;
  return (faits, total);
}
