import { Router } from 'express';
import { q } from './db.js';
import { requireAuth, requireRole } from './auth.js';
import { getReglages } from './reglages.js';

export const rapportsRouter = Router();
rapportsRouter.use(requireAuth, requireRole('admin'));

/* ---------- Activité : journal d'audit lisible ---------- */
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

/* ---------- Finance : agrégats de comptabilité ---------- */
rapportsRouter.get('/finance', async (_req, res) => {
  const reglages = await getReglages();

  // Toutes les missions non annulées avec leurs totaux.
  const missions = (await q(`
    SELECT m.*, v.nom AS voyageur_nom, v.comm_mode AS v_mode, v.comm_val AS v_val,
           COALESCE((SELECT SUM(kg*prix_kg) FROM produits_mission WHERE mission_id=m.id),0) AS revenu,
           COALESCE((SELECT SUM(usd*taux)   FROM tranches_devises WHERE mission_id=m.id),0) AS marchandise_da,
           COALESCE((SELECT SUM(montant)    FROM paiements        WHERE mission_id=m.id),0) AS encaisse
    FROM missions m JOIN voyageurs v ON v.id=m.voyageur_id
    WHERE m.statut <> 'annulee'`)).rows;

  const fraisDe = (m) =>
    Number(m.billet) + Number(m.dem_cout) + Number(m.frais_visa || 0) +
    Number(m.jours) * Number(m.budget_jour) + Number(m.bea) + Number(m.douane) +
    Number(m.autres) + Number(m.poche_frais_carte || 0);

  let sortis = 0, revenus = 0, netAgence = 0, creances = 0, partVoyageurs = 0;
  const parMois = {};
  const cloturees = missions.filter((m) => m.statut === 'cloturee');

  for (const m of cloturees) {
    const frais = fraisDe(m);
    const march = Number(m.marchandise_da);
    const attendu = Number(m.attendu ?? 0);
    const benef = attendu - frais - march;
    const comm = Number(m.commission ?? 0);
    const primes = Number(m.primes ?? 0);
    const net = benef - comm - primes;
    const solde = attendu - Number(m.encaisse);

    sortis += frais + march;
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
    par_mois: Object.entries(parMois)
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([mois, net]) => ({ mois, net })),
    missions: cloturees.map((m) => ({
      id: m.id, code: m.code, voyageur: m.voyageur_nom,
      depart: m.depart, frais: fraisDe(m), marchandise: Number(m.marchandise_da),
      attendu: Number(m.attendu ?? 0), commission: Number(m.commission ?? 0),
      encaisse: Number(m.encaisse), solde: Number(m.attendu ?? 0) - Number(m.encaisse),
    })),
  });
});
