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
    SELECT m.*, v.nom AS voyageur_nom, v.devise_compte, v.comm_mode AS v_mode, v.comm_val AS v_val,
           COALESCE((SELECT SUM(kg*prix_kg) FROM produits_mission WHERE mission_id=m.id),0) AS revenu,
           COALESCE((SELECT SUM(usd) FROM tranches_devises
                     WHERE mission_id=m.id AND motif='voyage'),0) AS marchandise_devise,
           COALESCE((SELECT SUM(usd*taux) FROM tranches_devises
                     WHERE mission_id=m.id AND motif='voyage'),0) AS marchandise_da,
           COALESCE((SELECT SUM(usd*taux) FROM tranches_devises
                     WHERE mission_id=m.id AND motif='poche'),0)  AS poche_da,
           COALESCE((SELECT SUM(montant)    FROM paiements        WHERE mission_id=m.id),0) AS encaisse
    FROM missions m JOIN voyageurs v ON v.id=m.voyageur_id
    WHERE m.statut <> 'annulee'`)).rows;

  // Même formule que missions.js : poche réelle (tranches) remplace jours × budget,
  // et les taxes de carte (au taux PARALLÈLE des réglages) sont une dépense —
  // réelles si facturé, sinon potentielles. La marchandise n'est PAS une dépense.
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
  const fraisDe = (m) =>
    Number(m.billet) + Number(m.dem_cout) + Number(m.frais_visa || 0) +
    (Number(m.poche_da) > 0 ? Number(m.poche_da) : Number(m.jours) * Number(m.budget_jour)) +
    Number(m.douane) + taxesCarteDe(m) + Number(m.autres) + Number(m.manques_da || 0);

  let sortis = 0, revenus = 0, netAgence = 0, creances = 0, partVoyageurs = 0;
  const parMois = {};
  const cloturees = missions.filter((m) => m.statut === 'cloturee');

  for (const m of cloturees) {
    const frais = fraisDe(m);
    const attendu = Number(m.attendu ?? 0);
    // Marchandise = argent déplacé, PAS une dépense — ses taxes sont déjà dans frais.
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
