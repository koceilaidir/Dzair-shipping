import { Router } from 'express';
import { q } from './db.js';
import { requireAuth, requireRole } from './auth.js';
import { getReglages } from './reglages.js';

export const rapportsRouter = Router();
rapportsRouter.use(requireAuth, requireRole('admin', 'voyageur'));

rapportsRouter.get('/activite', async (_req, res) => {
  const { rows } = await q(`
    SELECT a.id, a.action, a.entite, a.entite_id, a.details, a.created_at,
           u.nom AS auteur
    FROM audit_log a
    LEFT JOIN users u ON u.id = a.user_id
    ORDER BY a.created_at DESC
    LIMIT 300`);
  res.json(rows);
});

rapportsRouter.get('/creances', async (_req, res) => {
  const missions = (await q(`
    SELECT m.id, m.code, m.depot, m.attendu, m.cloture_date, m.depart, v.nom AS voyageur,
           COALESCE((SELECT SUM(montant) FROM paiements WHERE mission_id = m.id), 0) AS encaisse
    FROM missions m JOIN voyageurs v ON v.id = m.voyageur_id
    WHERE m.statut = 'cloturee'
    ORDER BY m.cloture_date DESC NULLS LAST, m.id DESC`)).rows;

  const out = [];
  let totalDu = 0, totalEncaisse = 0;
  for (const m of missions) {

    const dus = (await q(`
      SELECT c.id AS chambre_id, c.nom AS chambre,
             SUM((a.quantite - COALESCE(a.manquants,0) - COALESCE(a.saisis,0)) *
                 CASE WHEN l.mode = 'kg' THEN l.prix * l.poids_total / l.quantite ELSE l.prix END) AS du
      FROM affectations a
      JOIN bon_lignes l ON l.id = a.ligne_id
      JOIN bons b ON b.id = l.bon_id
      JOIN chambres c ON c.id = b.chambre_id
      WHERE a.mission_id = $1 GROUP BY c.id, c.nom ORDER BY c.nom`, [m.id])).rows;
    const verses = (await q(`
      SELECT p.id, p.montant, p.date, p.note, p.chambre_id, c.nom AS chambre,
             p.devise, p.taux, p.montant_devise, p.moyen
      FROM paiements p LEFT JOIN chambres c ON c.id = p.chambre_id
      WHERE p.mission_id = $1 ORDER BY p.date, p.id`, [m.id])).rows;
    const statuts = (await q(
      `SELECT chambre_id, statut FROM mission_depots WHERE mission_id = $1`, [m.id])).rows;
    const stMap = new Map(statuts.map((s) => [s.chambre_id, s.statut]));
    const encParChambre = {};
    for (const p of verses) {
      if (p.chambre_id) encParChambre[p.chambre_id] = (encParChambre[p.chambre_id] || 0) + Number(p.montant);
    }
    const attendu = Number(m.attendu ?? 0), encaisse = Number(m.encaisse);
    const reste = attendu - encaisse;
    totalDu += Math.max(0, reste);
    totalEncaisse += encaisse;
    out.push({
      id: m.id, code: m.code, voyageur: m.voyageur, depot: m.depot,
      cloture_date: m.cloture_date, depart: m.depart,
      attendu, encaisse, reste,
      depots: dus.map((d) => ({
        chambre_id: d.chambre_id, chambre: d.chambre, du: Math.round(Number(d.du)),
        encaisse: Math.round(encParChambre[d.chambre_id] || 0),
        statut: stMap.get(d.chambre_id) || 'a_verifier',
      })),
      versements: verses.map((p) => ({
        id: p.id, montant: Number(p.montant), date: p.date, note: p.note, chambre: p.chambre,
        devise: p.devise || 'DA', taux: p.taux == null ? null : Number(p.taux),
        montant_devise: p.montant_devise == null ? null : Number(p.montant_devise),
        moyen: p.moyen || 'cash',
      })),
    });
  }

  const comptes = (await q(`
    SELECT nom, devise_compte, solde_devises FROM voyageurs
    WHERE solde_devises > 0 ORDER BY solde_devises DESC`)).rows;
  res.json({
    total_a_recuperer: Math.round(totalDu),
    total_encaisse: Math.round(totalEncaisse),
    missions: out,
    comptes: comptes.map((c) => ({
      voyageur: c.nom, devise: c.devise_compte, solde: Number(c.solde_devises),
    })),
  });
});

rapportsRouter.get('/finance', async (_req, res) => {
  const reglages = await getReglages();

  const missions = (await q(`
    SELECT m.*, v.nom AS voyageur_nom, v.devise_compte, v.comm_mode AS v_mode, v.comm_val AS v_val,
           COALESCE((SELECT SUM(kg*prix_kg) FROM produits_mission WHERE mission_id=m.id),0) AS revenu,
           COALESCE((SELECT SUM(usd) FROM tranches_devises
                     WHERE mission_id=m.id AND motif='voyage'),0) AS marchandise_devise,
           COALESCE((SELECT SUM(usd*taux) FROM tranches_devises
                     WHERE mission_id=m.id AND motif='voyage'),0) AS marchandise_da,
           COALESCE((SELECT SUM(usd*taux) FROM tranches_devises
                     WHERE mission_id=m.id AND motif='poche'),0)  AS poche_da,
           COALESCE((SELECT SUM(usd*taux) FROM tranches_devises
                     WHERE mission_id=m.id AND motif='reste'),0)  AS reste_da,
           COALESCE((SELECT SUM(montant)    FROM paiements        WHERE mission_id=m.id),0) AS encaisse
    FROM missions m JOIN voyageurs v ON v.id=m.voyageur_id
    WHERE m.statut <> 'annulee'`)).rows;

  const pct = Number(reglages.frais_carte_pct || 0) / 100;
  const taxesCarteDe = (m) => {
    const md = Number(m.marchandise_da), mdev = Number(m.marchandise_devise);
    const tMoyen = mdev > 0 ? md / mdev : Number(reglages.taux_officiel);
    const tp = Number(m.devise_compte === 'EUR'
      ? reglages.taux_parallele_eur : reglages.taux_parallele_usd);
    const tPar = Number.isFinite(tp) && tp > 0 ? tp : tMoyen;
    return m.factures_total != null
      ? Math.round(Number(m.factures_total) * pct * tPar)
      : Math.round(mdev * pct * tPar);
  };

  const fraisDetailDe = (m) => ({
    billets: Number(m.billet),
    poche: Math.max(0,
      (Number(m.poche_da) > 0 ? Number(m.poche_da) : Number(m.jours) * Number(m.budget_jour))
        - Number(m.reste_da || 0)),
    douane: Number(m.douane),
    carte: taxesCarteDe(m),
    demarches: Number(m.dem_cout) + Number(m.frais_visa || 0),
    autres: Number(m.autres) + Number(m.manques_da || 0) + Number(m.saisie_da || 0) +
      (m.valise_sup ? Number(m.valise_sup_prix || 0) : 0),
  });
  const fraisDe = (m) => Object.values(fraisDetailDe(m)).reduce((s, v) => s + v, 0);

  let sortis = 0, revenus = 0, netAgence = 0, creances = 0, partVoyageurs = 0;
  const parMois = {};
  const fraisDetail = { billets: 0, poche: 0, douane: 0, carte: 0, demarches: 0, autres: 0 };
  const cloturees = missions.filter((m) => m.statut === 'cloturee');

  for (const m of cloturees) {
    const detail = fraisDetailDe(m);
    for (const k of Object.keys(fraisDetail)) fraisDetail[k] += detail[k];
    const frais = fraisDe(m);
    const attendu = Number(m.attendu ?? 0);

    const benef = attendu - frais;
    const comm = Number(m.commission ?? 0);
    const primes = Number(m.primes ?? 0);
    const net = benef - comm - primes;
    const solde = attendu - Number(m.encaisse);

    sortis += frais;
    revenus += attendu;
    netAgence += net;
    partVoyageurs += comm + primes;
    if (solde > 0) creances += solde;

    const mois = String(m.depart || m.cloture_date || '').slice(0, 7) || 'inconnu';
    parMois[mois] = (parMois[mois] || 0) + net;
  }

  const enCours = missions.filter((m) => m.statut === 'encours').length;

  res.json({
    reglages,
    totaux: {
      sortis, revenus, net_agence: netAgence, creances,
      part_voyageurs: partVoyageurs,
      missions_cloturees: cloturees.length, missions_en_cours: enCours,
    },
    frais_detail: Object.fromEntries(
      Object.entries(fraisDetail).map(([k, v]) => [k, Math.round(v)])),
    par_mois: Object.entries(parMois)
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([mois, net]) => ({ mois, net })),
    missions: cloturees.map((m) => ({
      id: m.id, code: m.code, voyageur: m.voyageur_nom,
      depart: m.depart, cloture_date: m.cloture_date,
      frais: fraisDe(m), frais_detail: fraisDetailDe(m),
      marchandise: Number(m.marchandise_da),
      attendu: Number(m.attendu ?? 0), commission: Number(m.commission ?? 0),
      primes: Number(m.primes ?? 0),
      encaisse: Number(m.encaisse), solde: Number(m.attendu ?? 0) - Number(m.encaisse),
    })),
  });
});
