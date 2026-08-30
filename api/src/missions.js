import { Router } from 'express';
import { z } from 'zod';
import { q } from './db.js';
import { requireAuth, requireRole } from './auth.js';
import { getReglages } from './reglages.js';

export const missionsRouter = Router();
missionsRouter.use(requireAuth, requireRole('admin', 'voyageur'));

const missionBase = z.object({
  vol: z.string().max(60).optional().default(''),
  depart: z.string().max(10).optional().nullable(),
  retour: z.string().max(10).optional().nullable(),
  jours: z.coerce.number().int().min(1).max(60).default(5),
  budget_jour: z.coerce.number().nonnegative().default(3000),
  billet: z.coerce.number().nonnegative().default(0),
  dem_type: z.enum(['premiere', 'renouvellement', 'visa_double', 'multiple']).default('multiple'),
  dem_cout: z.coerce.number().nonnegative().default(0),
  bea: z.coerce.number().nonnegative().default(0),
  douane: z.coerce.number().nonnegative().default(0),
  autres: z.coerce.number().nonnegative().default(0),
  objectif: z.coerce.number().nonnegative().default(20000),
  val_declaree: z.coerce.number().nonnegative().optional().nullable(),
});

const frais = (m, pocheDA = 0, taxesCarteDA = 0, resteDA = 0) =>
  Number(m.billet) + Number(m.dem_cout) + Number(m.frais_visa || 0) +
  Math.max(0, (pocheDA > 0 ? pocheDA : Number(m.jours) * Number(m.budget_jour)) - resteDA) +
  Number(m.douane) + taxesCarteDA + Number(m.autres) + Number(m.manques_da || 0) +
  (m.valise_sup ? Number(m.valise_sup_prix || 0) : 0) +
  Number(m.saisie_da || 0);

function tauxParallele(reglages, devise, secours) {
  const t = Number(devise === 'EUR' ? reglages.taux_parallele_eur : reglages.taux_parallele_usd);
  return Number.isFinite(t) && t > 0 ? t : secours;
}

async function valiseDe(id) {
  const libre = (await q(
    `SELECT COALESCE(SUM(kg),0) AS kg, COALESCE(SUM(kg*prix_kg),0) AS rev
     FROM produits_mission WHERE mission_id = $1`, [id])).rows[0];
  const aff = (await q(
    `SELECT a.quantite, l.mode, l.prix, l.poids_total, l.quantite AS q_ligne
     FROM affectations a JOIN bon_lignes l ON l.id = a.ligne_id WHERE a.mission_id = $1`, [id])).rows;
  let kg = Number(libre.kg), rev = Number(libre.rev);
  for (const a of aff) {
    const pu = Number(a.poids_total) / Number(a.q_ligne);
    const gp = a.mode === 'kg' ? Number(a.prix) * pu : Number(a.prix);
    kg += Number(a.quantite) * pu;
    rev += Number(a.quantite) * gp;
  }
  return { kg, rev };
}

async function sommesTranches(id) {
  const r = (await q(
    `SELECT
       COALESCE(SUM(usd)        FILTER (WHERE motif = 'voyage'), 0) AS march_devise,
       COALESCE(SUM(usd * taux) FILTER (WHERE motif = 'voyage'), 0) AS march_da,
       COALESCE(SUM(usd * taux) FILTER (WHERE motif = 'poche'),  0) AS poche_da,
       COALESCE(SUM(usd * taux) FILTER (WHERE motif = 'reste'),  0) AS reste_da
     FROM tranches_devises WHERE mission_id = $1`, [id])).rows[0];
  return {
    marchDevise: Number(r.march_devise),
    marchDA: Number(r.march_da),
    pocheDA: Number(r.poche_da),
    resteDA: Number(r.reste_da),
  };
}

function taxesArrivee(baseDevise, reglages, marge30) {
  const ca = baseDevise * Number(reglages.taux_officiel);
  const douane = ca * 0.05;
  const ifu = (ca + douane) * (marge30 ? 1.3 : 1) * 0.005;
  return Math.round(douane + ifu);
}

function marge30De(ifuMarge, reglages) {
  return ifuMarge == null ? Number(reglages.ifu_marge_30 ?? 1) > 0 : !!ifuMarge;
}

function basePrevision(marchDevise, declare, reglages) {
  const pct = Number(reglages.frais_carte_pct || 0) / 100;
  return declare > 0 ? declare : marchDevise * (1 - pct);
}

async function declareDe(id) {
  return Number((await q(
    `SELECT COALESCE(SUM(quantite * COALESCE(prix_declare, 0)), 0) AS t
     FROM affectations WHERE mission_id = $1 AND emplacement = 'soute'`,
    [id])).rows[0].t);
}

async function majDouaneEstimee(id) {
  const m = (await q('SELECT statut, taxes_reelles FROM missions WHERE id = $1', [id])).rows[0];

  if (!m || m.statut === 'cloturee' || m.taxes_reelles != null) return;
  const { marchDevise } = await sommesTranches(id);
  const declare = await declareDe(id);
  const reglages = await getReglages();
  await q('UPDATE missions SET douane = $1 WHERE id = $2',
    [taxesArrivee(basePrevision(marchDevise, declare, reglages), reglages, true), id]);
}

const audit = (userId, action, entite, id, details) => q(
  `INSERT INTO audit_log (user_id, action, entite, entite_id, details) VALUES ($1,$2,$3,$4,$5)`,
  [userId, action, entite, id, JSON.stringify(details)]);

const moisDe = (d) => (d || new Date().toISOString().slice(0, 10)).slice(0, 7);

function joursEntre(dep, ret) {
  if (!dep || !ret) return 4;
  const a = new Date(dep), b = new Date(ret);
  const j = Math.round((b - a) / 86400000) - 1;
  return j > 0 && j <= 60 ? j : 1;
}

missionsRouter.get('/', async (_req, res) => {
  const { rows } = await q(`
    SELECT m.*, v.nom AS voyageur_nom, v.devise_compte,
           COALESCE((SELECT SUM(kg) FROM produits_mission p WHERE p.mission_id = m.id), 0)
             + COALESCE((SELECT SUM(a.quantite * l.poids_total / l.quantite)
                         FROM affectations a JOIN bon_lignes l ON l.id = a.ligne_id
                         WHERE a.mission_id = m.id), 0)                          AS kg_total,
           COALESCE((SELECT SUM(kg * prix_kg) FROM produits_mission p WHERE p.mission_id = m.id), 0)
             + COALESCE((SELECT SUM((a.quantite - COALESCE(a.saisis, 0)) * CASE WHEN l.mode = 'kg'
                                     THEN l.prix * l.poids_total / l.quantite ELSE l.prix END)
                         FROM affectations a JOIN bon_lignes l ON l.id = a.ligne_id
                         WHERE a.mission_id = m.id), 0)                          AS revenu,
           COALESCE((SELECT SUM(usd) FROM tranches_devises t
                     WHERE t.mission_id = m.id AND t.motif = 'voyage'), 0) AS marchandise_devise,
           COALESCE((SELECT SUM(usd * taux) FROM tranches_devises t
                     WHERE t.mission_id = m.id AND t.motif = 'voyage'), 0) AS marchandise_da,
           COALESCE((SELECT SUM(usd * taux) FROM tranches_devises t
                     WHERE t.mission_id = m.id AND t.motif = 'poche'), 0)  AS poche_da,
           COALESCE((SELECT SUM(usd * taux) FROM tranches_devises t
                     WHERE t.mission_id = m.id AND t.motif = 'reste'), 0)  AS reste_da,
           COALESCE((SELECT SUM(a.quantite * COALESCE(a.prix_declare, 0))
                     FROM affectations a WHERE a.mission_id = m.id
                       AND a.emplacement = 'soute'), 0)                    AS declare_total
    FROM missions m
    JOIN voyageurs v ON v.id = m.voyageur_id
    WHERE m.statut <> 'annulee'
    ORDER BY m.depart DESC NULLS LAST, m.id DESC
  `);

  const reglages = await getReglages();
  const pct = Number(reglages.frais_carte_pct || 0) / 100;
  res.json(rows.map((r) => {
    const md = Number(r.marchandise_da), mdev = Number(r.marchandise_devise);
    const tMoyen = mdev > 0 ? md / mdev : Number(reglages.taux_officiel);
    const tPar = tauxParallele(reglages, r.devise_compte, tMoyen);
    const taxes = r.statut === 'cloturee' && r.factures_total != null
      ? Math.round(Number(r.factures_total) * pct * tPar)
      : Math.round(mdev * pct * tPar);
    const decl = Number(r.declare_total);
    const douane = r.taxes_reelles != null
      ? Number(r.taxes_reelles)
      : r.statut === 'cloturee'
        ? Number(r.douane)
        : taxesArrivee(basePrevision(mdev, decl, reglages), reglages, true);
    return { ...r, taxes_carte: taxes, douane };
  }));
});

missionsRouter.get('/:id', async (req, res) => {
  const id = Number(req.params.id);
  const m = (await q(
    `SELECT m.*, v.nom AS voyageur_nom, v.comm_mode AS v_comm_mode,
            v.comm_val AS v_comm_val, v.bagages AS v_bagages,
            v.devise_compte AS v_devise, v.solde_devises AS v_solde,
            v.allocation_eligible AS v_alloc_eligible,
            v.allocation_derniere AS v_alloc_derniere
     FROM missions m JOIN voyageurs v ON v.id = m.voyageur_id WHERE m.id = $1`,
    [id])).rows[0];
  if (!m) return res.status(404).json({ error: 'Mission introuvable.' });
  const produits = (await q(
    'SELECT * FROM produits_mission WHERE mission_id = $1 ORDER BY id', [id])).rows;
  const paiements = (await q(
    'SELECT * FROM paiements WHERE mission_id = $1 ORDER BY date, id', [id])).rows;
  const tranches = (await q(
    'SELECT * FROM tranches_devises WHERE mission_id = $1 ORDER BY id', [id])).rows;

  const affectations = (await q(
    `SELECT a.id, a.ligne_id, a.quantite, a.manquants, a.prix_declare,
            a.emplacement, a.saisis,
            l.produit, l.mode, l.prix, l.manque_rmb,
            l.poids_total / l.quantite AS poids_unit,
            CASE WHEN l.mode = 'kg' THEN l.prix * l.poids_total / l.quantite ELSE l.prix END AS gain_piece,
            c.nom AS chambre_nom
     FROM affectations a
     JOIN bon_lignes l ON l.id = a.ligne_id
     JOIN bons b ON b.id = l.bon_id
     JOIN chambres c ON c.id = b.chambre_id
     WHERE a.mission_id = $1 ORDER BY a.id`, [id])).rows;

  if (m.statut !== 'cloturee' && m.taxes_reelles == null) {
    const reglages = await getReglages();
    const marchDevise = tranches
      .filter((t) => t.motif === 'voyage')
      .reduce((s, t) => s + Number(t.usd), 0);
    const declare = affectations
      .filter((a) => a.emplacement !== 'main')
      .reduce((s, a) => s + Number(a.quantite) * Number(a.prix_declare || 0), 0);
    const d = taxesArrivee(basePrevision(marchDevise, declare, reglages), reglages, true);
    if (d !== Number(m.douane)) {
      await q('UPDATE missions SET douane = $1 WHERE id = $2', [d, id]);
      m.douane = d;
    }
  }
  const photo = (await q(
    `SELECT 1 FROM mission_docs WHERE mission_id = $1 AND type = 'bon_douane' LIMIT 1`, [id])).rows[0];
  res.json({ ...m, produits, paiements, tranches, affectations, arrivee_photo: !!photo });
});

missionsRouter.post('/', async (req, res) => {
  const parsed = missionBase.extend({
    voyageur_ids: z.array(z.coerce.number().int()).min(1),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Données invalides.' });
  const { voyageur_ids, ...base } = parsed.data;
  const mois = moisDe(base.depart);
  const reglages = await getReglages();

  if (!base.dem_cout) {
    base.dem_cout = {
      premiere: reglages.prix_premiere,
      renouvellement: reglages.prix_renouvellement,
      visa_double: reglages.prix_visa_double,
      multiple: 0,
    }[base.dem_type] ?? 0;
  }
  const fraisVisa = reglages.frais_depot_visa ?? 6800;
  if (!req.body.budget_jour) base.budget_jour = reglages.budget_jour_defaut ?? 3000;

  base.jours = joursEntre(base.depart, base.retour);

  if (base.vol && base.depart) {
    const dup = (await q(
      `SELECT id, voyageur_id FROM missions
       WHERE vol = $1 AND depart = $2 AND statut <> 'annulee'
         AND created_at > now() - interval '30 seconds'`,
      [base.vol, base.depart])).rows;
    if (dup.length && voyageur_ids.every((v) => dup.some((d) => d.voyageur_id === v))) {
      return res.status(200).json(
        (await q('SELECT * FROM missions WHERE id = ANY($1)', [dup.map((d) => d.id)])).rows);
    }
  }

  const dateRef = base.retour || base.depart || new Date().toISOString().slice(0, 10);
  const bloques = [];
  for (const vid of voyageur_ids) {
    const { rows } = await q(
      `SELECT v.nom, v.statut_dispo, v.passeport_expire, v.autorisation_expire, COUNT(m.id) AS n
       FROM voyageurs v
       LEFT JOIN missions m ON m.voyageur_id = v.id
         AND m.statut <> 'annulee' AND to_char(m.depart, 'YYYY-MM') = $2
       WHERE v.id = $1 GROUP BY v.id`, [vid, mois]);
    const r = rows[0];
    if (!r) return res.status(400).json({ error: `Voyageur ${vid} introuvable.` });
    if (r.statut_dispo === 'indisponible') bloques.push(`${r.nom} : marqué indisponible`);
    if (Number(r.n) >= 2) bloques.push(`${r.nom} : déjà 2 missions ce mois-là (limite légale)`);
    if (r.passeport_expire && String(r.passeport_expire).slice(0, 10) <= dateRef) {
      bloques.push(`${r.nom} : passeport expiré au retour prévu`);
    }
    if (r.autorisation_expire && String(r.autorisation_expire).slice(0, 10) <= dateRef) {
      bloques.push(`${r.nom} : autorisation ANAE expirée au retour prévu`);
    }
  }
  if (bloques.length) {
    return res.status(409).json({ error: '🚫 ' + bloques.join(' · ') });
  }

  const created = [];
  for (const vid of voyageur_ids) {
    const v = (await q('SELECT * FROM voyageurs WHERE id = $1', [vid])).rows[0];
    const kgSoute = (Number(v.bagages) || 2) * 23;
    const seq = (await q('SELECT COUNT(*) AS n FROM missions')).rows[0].n;
    const code = 'MSN-' + String(Number(seq) + 1).padStart(3, '0');
    const { rows } = await q(
      `INSERT INTO missions (voyageur_id, code, vol, depart, retour, jours, budget_jour,
         billet, dem_type, dem_cout, bea, douane, autres, objectif, kg_soute, val_declaree,
         frais_visa, statut)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,'encours') RETURNING *`,
      [vid, code, base.vol, base.depart, base.retour, base.jours, base.budget_jour,
       base.billet, base.dem_type, base.dem_cout, base.bea, base.douane, base.autres,
       base.objectif, kgSoute, base.val_declaree ?? null, fraisVisa]);
    created.push(rows[0]);
    await q(`INSERT INTO audit_log (user_id, action, entite, entite_id, details)
             VALUES ($1,'create','mission',$2,$3)`,
      [req.user.sub, rows[0].id, JSON.stringify({ code, voyageur: v.nom })]);

    const nMois = Number((await q(
      `SELECT COUNT(*) AS n FROM missions
       WHERE voyageur_id = $1 AND statut <> 'annulee' AND to_char(depart,'YYYY-MM') = $2`,
      [vid, mois])).rows[0].n);
    if (nMois >= 2 && v.statut_dispo !== 'indisponible') {
      await q(`UPDATE voyageurs SET statut_dispo = 'limite' WHERE id = $1`, [vid]);
    }
  }
  res.status(201).json(created);
});

missionsRouter.put('/:id', async (req, res) => {
  const id = Number(req.params.id);
  const parsed = missionBase.partial().extend({
    statut: z.enum(['planifiee', 'encours', 'annulee']).optional(),
    cabine: z.boolean().optional(),
    kg_soute: z.coerce.number().positive().optional(),
    check_depart: z.record(z.string(), z.boolean()).optional(),
    check_retour: z.record(z.string(), z.boolean()).optional(),
    frais_visa: z.coerce.number().nonnegative().optional(),
    allocation_utilisee: z.boolean().optional(),
    heure_depart: z.string().max(5).nullable().optional(),
    heure_arrivee: z.string().max(5).nullable().optional(),
    poche_mode: z.enum(['cash_da', 'rmb_alipay', 'cash_devise', 'carte']).optional(),
    valise_close: z.boolean().optional(),

    valise_sup: z.boolean().optional(),
    valise_sup_prix: z.coerce.number().nonnegative().optional(),
    valise_sup_kg: z.coerce.number().positive().optional(),
    bagage_main: z.boolean().optional(),
    bagage_main_kg: z.coerce.number().positive().optional(),
    bagage_main_close: z.boolean().optional(),

    liquide_remis: z.coerce.number().nonnegative().nullable().optional(),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Données invalides.' });

  const cur = (await q('SELECT * FROM missions WHERE id = $1', [id])).rows[0];
  if (!cur) return res.status(404).json({ error: 'Mission introuvable.' });
  if (cur.statut === 'cloturee') {
    return res.status(409).json({ error: 'Mission clôturée — la compta passée ne se modifie pas.' });
  }
  const m = { ...cur, ...parsed.data };

  if (parsed.data.depart !== undefined || parsed.data.retour !== undefined) {
    m.jours = joursEntre(m.depart, m.retour);
  }

  m.poche_frais_carte = 0;
  const { rows } = await q(
    `UPDATE missions SET vol=$1, depart=$2, retour=$3, jours=$4, budget_jour=$5, billet=$6,
       dem_type=$7, dem_cout=$8, bea=$9, douane=$10, autres=$11, objectif=$12,
       kg_soute=$13, cabine=$14, val_declaree=$15, statut=$16,
       check_depart=$17, check_retour=$18, frais_visa=$19, allocation_utilisee=$20,
       heure_depart=$21, heure_arrivee=$22, poche_mode=$23, poche_frais_carte=$24,
       valise_close=$25, valise_sup=$26, valise_sup_prix=$27, valise_sup_kg=$28,
       bagage_main=$29, bagage_main_kg=$30, bagage_main_close=$31, liquide_remis=$32
     WHERE id=$33 RETURNING *`,
    [m.vol, m.depart, m.retour, m.jours, m.budget_jour, m.billet, m.dem_type, m.dem_cout,
     m.bea, m.douane, m.autres, m.objectif, m.kg_soute, m.cabine, m.val_declaree, m.statut,
     JSON.stringify(m.check_depart ?? {}), JSON.stringify(m.check_retour ?? {}),
     m.frais_visa ?? 0, m.allocation_utilisee ?? false,
     m.heure_depart ?? null, m.heure_arrivee ?? null,
     m.poche_mode ?? 'cash_da', m.poche_frais_carte ?? 0, m.valise_close ?? false,
     m.valise_sup ?? false, m.valise_sup_prix ?? 0, m.valise_sup_kg ?? 23,
     m.bagage_main ?? false, m.bagage_main_kg ?? 8, m.bagage_main_close ?? false,
     m.liquide_remis ?? null, id]);

  if (parsed.data.allocation_utilisee === true) {
    await q('UPDATE voyageurs SET allocation_derniere = $1 WHERE id = $2',
      [m.depart ?? new Date().toISOString().slice(0, 10), cur.voyageur_id]);
  } else if (parsed.data.allocation_utilisee === false && cur.allocation_utilisee) {
    await q('UPDATE voyageurs SET allocation_derniere = NULL WHERE id = $1', [cur.voyageur_id]);
  }

  const champs = Object.keys(parsed.data);
  const details = { code: cur.code };
  if (parsed.data.valise_close !== undefined) {
    details.valise = parsed.data.valise_close ? 'complète' : 'rouverte';

    if (parsed.data.valise_close === false) {
      await q(`UPDATE factures SET statut = 'annulee' WHERE mission_id = $1 AND statut = 'emise'`, [id]);
    }
  }
  else if (parsed.data.bagage_main_close !== undefined && champs.length === 1) {
    details.bagage_main = parsed.data.bagage_main_close ? 'complet' : 'rouvert';
  }
  else if (champs.length === 1 && (champs[0] === 'check_depart' || champs[0] === 'check_retour')) {
    details.check = champs[0] === 'check_depart' ? 'départ' : 'retour';
  } else details.champs = champs;
  await audit(req.user.sub, 'update', 'mission', id, details);
  res.json(rows[0]);
});

async function purgeMission(id, code, userId) {
  await q('DELETE FROM paiements WHERE mission_id = $1', [id]);
  await q('DELETE FROM tranches_devises WHERE mission_id = $1', [id]);
  await q('DELETE FROM demandes_suppression WHERE mission_id = $1', [id]);
  await q('DELETE FROM missions WHERE id = $1', [id]);
  await q(`INSERT INTO audit_log (user_id, action, entite, entite_id, details)
           VALUES ($1,'delete','mission',$2,$3)`,
    [userId, id, JSON.stringify({ code })]);
}

missionsRouter.delete('/:id', async (req, res) => {
  const id = Number(req.params.id);
  const m = (await q('SELECT statut, code FROM missions WHERE id = $1', [id])).rows[0];
  if (!m) return res.status(404).json({ error: 'Mission introuvable.' });

  if (m.statut !== 'cloturee') {
    await purgeMission(id, m.code, req.user.sub);
    return res.json({ ok: true, supprimee: true });
  }

  const admins = (await q(`SELECT id FROM users WHERE role='admin' AND actif`)).rows.map((r) => r.id);
  let dem = (await q(
    `SELECT * FROM demandes_suppression WHERE mission_id=$1 AND statut='en_attente'`,
    [id])).rows[0];
  if (!dem) {
    dem = (await q(
      `INSERT INTO demandes_suppression (mission_id, demandeur, approbateurs)
       VALUES ($1,$2,$3) RETURNING *`,
      [id, req.user.sub, JSON.stringify([req.user.sub])])).rows[0];
    await q(`INSERT INTO audit_log (user_id, action, entite, entite_id, details)
             VALUES ($1,'demande_suppression','mission',$2,$3)`,
      [req.user.sub, id, JSON.stringify({ code: m.code })]);
  } else {
    const appr = new Set([...(dem.approbateurs || []), req.user.sub]);
    dem.approbateurs = [...appr];
    await q('UPDATE demandes_suppression SET approbateurs=$1 WHERE id=$2',
      [JSON.stringify(dem.approbateurs), dem.id]);
  }

  const tousOk = admins.every((a) => dem.approbateurs.includes(a));
  if (tousOk) {
    await purgeMission(id, m.code, req.user.sub);
    return res.json({ ok: true, supprimee: true });
  }
  const manque = admins.filter((a) => !dem.approbateurs.includes(a)).length;
  return res.json({
    ok: true,
    supprimee: false,
    message: `Demande de suppression enregistrée. En attente de ${manque} autre(s) admin(s).`,
  });
});

missionsRouter.post('/:id/produits', async (req, res) => {
  const id = Number(req.params.id);
  const parsed = z.object({
    nom: z.string().min(1).max(160),
    kg: z.coerce.number().positive(),
    prix_kg: z.coerce.number().positive(),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Produit invalide.' });
  const cur = (await q('SELECT statut, valise_close FROM missions WHERE id = $1', [id])).rows[0];
  if (!cur) return res.status(404).json({ error: 'Mission introuvable.' });
  if (cur.statut === 'cloturee' || cur.valise_close) {
    return res.status(409).json({ error: 'Valise clôturée — rouvre-la pour ajouter un produit.' });
  }
  const { rows } = await q(
    `INSERT INTO produits_mission (mission_id, nom, kg, prix_kg)
     VALUES ($1,$2,$3,$4) RETURNING *`,
    [id, parsed.data.nom, parsed.data.kg, parsed.data.prix_kg]);
  const mc = (await q('SELECT code FROM missions WHERE id = $1', [id])).rows[0];
  await audit(req.user.sub, 'valise_ajout', 'mission', id,
    { code: mc?.code, produit: parsed.data.nom, kg: parsed.data.kg, hors_inventaire: true });
  res.status(201).json(rows[0]);
});

missionsRouter.delete('/:id/produits/:pid', async (req, res) => {
  const cur = (await q('SELECT statut FROM missions WHERE id = $1',
    [Number(req.params.id)])).rows[0];
  if (!cur) return res.status(404).json({ error: 'Mission introuvable.' });
  if (cur.statut === 'cloturee') {
    return res.status(409).json({ error: 'Valise clôturée — on n’y touche plus.' });
  }
  await q('DELETE FROM produits_mission WHERE id = $1 AND mission_id = $2',
    [Number(req.params.pid), Number(req.params.id)]);
  res.json({ ok: true });
});

missionsRouter.post('/:id/cloture', async (req, res) => {
  const id = Number(req.params.id);
  const parsed = z.object({
    depot: z.string().max(120).optional().default(''),
    attendu: z.coerce.number().nonnegative(),
    encaisse: z.coerce.number().nonnegative().default(0),
    primes: z.coerce.number().nonnegative().default(0),
    invendus: z.string().max(1000).optional().default(''),
    factures_total: z.coerce.number().nonnegative().optional(),
    ifu_marge: z.boolean().optional(),

    manquants: z.array(z.object({
      affectation_id: z.coerce.number().int(),
      quantite: z.coerce.number().nonnegative(),
    })).optional().default([]),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Données invalides.' });

  const m = (await q(
    `SELECT m.*, v.comm_mode AS v_mode, v.comm_val AS v_val,
            v.devise_compte AS v_devise, v.solde_devises AS v_solde
     FROM missions m JOIN voyageurs v ON v.id = m.voyageur_id WHERE m.id = $1`,
    [id])).rows[0];
  if (!m) return res.status(404).json({ error: 'Mission introuvable.' });
  if (m.statut === 'cloturee') return res.status(409).json({ error: 'Déjà clôturée.' });

  const { kg } = await valiseDe(id);
  const d = parsed.data;

  if (d.factures_total == null) {
    const decl = await declareDe(id);
    if (decl > 0) d.factures_total = Math.round(decl * 100) / 100;
  }

  const reglagesM = await getReglages();
  let manquesDA = 0;
  for (const mq of d.manquants) {
    if (mq.quantite <= 0) continue;
    const a = (await q(
      `SELECT a.quantite, a.saisis, l.manque_rmb FROM affectations a JOIN bon_lignes l ON l.id = a.ligne_id
       WHERE a.id = $1 AND a.mission_id = $2`, [mq.affectation_id, id])).rows[0];
    if (!a) continue;

    const qte = Math.min(mq.quantite, Number(a.quantite) - Number(a.saisis || 0));
    await q('UPDATE affectations SET manquants = $1 WHERE id = $2', [qte, mq.affectation_id]);
    manquesDA += qte * Number(a.manque_rmb) * Number(reglagesM.taux_rmb || 0);
  }
  manquesDA = Math.round(manquesDA);
  await q('UPDATE missions SET manques_da = $1 WHERE id = $2', [manquesDA, id]);
  m.manques_da = manquesDA;

  const reglages = await getReglages();
  const marge30 = d.ifu_marge != null ? d.ifu_marge : marge30De(m.ifu_marge, reglages);
  const { marchDevise, marchDA, pocheDA, resteDA } = await sommesTranches(id);
  const pct = Number(reglages.frais_carte_pct || 0) / 100;
  const tMoyen = marchDevise > 0 ? marchDA / marchDevise : Number(reglages.taux_officiel);

  const tPar = tauxParallele(reglages, m.v_devise, tMoyen);
  let taxesCarteDA = Math.round(marchDevise * pct * tPar);
  if (d.factures_total != null) {

    const taxes = m.taxes_reelles != null
      ? Number(m.taxes_reelles)
      : taxesArrivee(d.factures_total, reglages, marge30);
    const fraisCarteDevise = d.factures_total * pct;
    taxesCarteDA = Math.round(fraisCarteDevise * tPar);

    const valDeclaree = Math.round(d.factures_total * Number(reglages.taux_officiel));
    const dispo = Number(m.v_solde) + marchDevise;
    const soldeNouveau = Math.max(0, dispo - d.factures_total - fraisCarteDevise);
    await q('UPDATE voyageurs SET solde_devises = $1 WHERE id = $2',
      [soldeNouveau, m.voyageur_id]);
    await q('UPDATE missions SET douane = $1, factures_total = $2, val_declaree = $3 WHERE id = $4',
      [taxes, d.factures_total, valDeclaree, id]);
    m.douane = taxes;
    m.val_declaree = valDeclaree;
  }

  const benefice = d.attendu - frais(m, pocheDA, taxesCarteDA, resteDA);

  const commission =
    m.v_mode === 'kg' ? Number(m.v_val) * kg :
    m.v_mode === 'pct' ? Math.max(0, benefice) * Number(m.v_val) / 100 :
    Number(m.v_val);

  const { rows } = await q(
    `UPDATE missions SET statut='cloturee', depot=$1, attendu=$2, primes=$3, invendus=$4,
       cloture_date=CURRENT_DATE, comm_mode=$5, comm_val=$6, commission=$7, ifu_marge=$8
     WHERE id=$9 RETURNING *`,
    [d.depot, d.attendu, d.primes, d.invendus, m.v_mode, m.v_val, commission, marge30, id]);
  if (d.encaisse > 0) {
    await q(`INSERT INTO paiements (mission_id, montant, note)
             VALUES ($1,$2,'encaissement clôture')`, [id, d.encaisse]);
  }
  await q(`INSERT INTO audit_log (user_id, action, entite, entite_id, details)
           VALUES ($1,'cloture','mission',$2,$3)`,
    [req.user.sub, id, JSON.stringify({ attendu: d.attendu, commission, marge_ifu_30: marge30 })]);
  res.json(rows[0]);
});

missionsRouter.post('/:id/arrivee', async (req, res) => {
  const id = Number(req.params.id);
  const parsed = z.object({
    taxes_reelles: z.coerce.number().nonnegative(),
    note: z.string().max(1000).optional().default(''),
    saisis: z.array(z.object({
      affectation_id: z.coerce.number().int(),
      quantite: z.coerce.number().nonnegative(),
    })).optional().default([]),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Données invalides.' });
  const m = (await q('SELECT statut, code FROM missions WHERE id = $1', [id])).rows[0];
  if (!m) return res.status(404).json({ error: 'Mission introuvable.' });
  if (m.statut === 'cloturee') {
    return res.status(409).json({ error: 'Mission clôturée — la compta passée ne se modifie pas.' });
  }
  const d = parsed.data;
  const reglages = await getReglages();
  let saisieDA = 0, nbSaisis = 0;
  for (const s of d.saisis) {
    const a = (await q(
      `SELECT a.quantite, l.manque_rmb FROM affectations a JOIN bon_lignes l ON l.id = a.ligne_id
       WHERE a.id = $1 AND a.mission_id = $2`, [s.affectation_id, id])).rows[0];
    if (!a) continue;
    const qte = Math.min(Math.max(0, s.quantite), Number(a.quantite));
    await q('UPDATE affectations SET saisis = $1 WHERE id = $2', [qte, s.affectation_id]);
    saisieDA += qte * Number(a.manque_rmb) * Number(reglages.taux_rmb || 0);
    nbSaisis += qte;
  }
  saisieDA = Math.round(saisieDA);
  const { rows } = await q(
    `UPDATE missions SET taxes_reelles = $1, douane = $1, arrivee_note = $2, saisie_da = $3
     WHERE id = $4 RETURNING *`,
    [Math.round(d.taxes_reelles), d.note, saisieDA, id]);
  await audit(req.user.sub, 'arrivee', 'mission', id,
    { code: m.code, taxes_da: Math.round(d.taxes_reelles), saisis: nbSaisis, saisie_da: saisieDA });
  res.json(rows[0]);
});

missionsRouter.post('/:id/arrivee/photo', async (req, res) => {
  const id = Number(req.params.id);
  const parsed = z.object({
    data: z.string().min(1),
    mime: z.string().max(60).optional().default('image/jpeg'),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Photo invalide.' });
  const m = (await q('SELECT code FROM missions WHERE id = $1', [id])).rows[0];
  if (!m) return res.status(404).json({ error: 'Mission introuvable.' });
  let buf;
  try { buf = Buffer.from(parsed.data.data, 'base64'); } catch { buf = null; }
  if (!buf || !buf.length) return res.status(400).json({ error: 'Photo illisible.' });
  if (buf.length > 6 * 1024 * 1024) return res.status(413).json({ error: 'Photo trop lourde (6 Mo max).' });
  await q(`DELETE FROM mission_docs WHERE mission_id = $1 AND type = 'bon_douane'`, [id]);
  await q(`INSERT INTO mission_docs (mission_id, type, mime, data) VALUES ($1,'bon_douane',$2,$3)`,
    [id, parsed.data.mime, buf]);
  await audit(req.user.sub, 'arrivee_photo', 'mission', id, { code: m.code, ko: Math.round(buf.length / 1024) });
  res.status(201).json({ ok: true });
});

missionsRouter.get('/:id/arrivee/photo', async (req, res) => {
  const doc = (await q(
    `SELECT mime, data FROM mission_docs WHERE mission_id = $1 AND type = 'bon_douane'
     ORDER BY id DESC LIMIT 1`, [Number(req.params.id)])).rows[0];
  if (!doc) return res.status(404).json({ error: 'Aucune photo.' });
  res.setHeader('Content-Type', doc.mime);
  res.send(doc.data);
});

missionsRouter.post('/:id/tranches', async (req, res) => {
  const id = Number(req.params.id);
  const parsed = z.object({
    montant: z.coerce.number().positive(),
    devise: z.enum(['USD', 'EUR', 'RMB', 'DA']).default('USD'),
    taux: z.coerce.number().positive().optional(),
    source: z.string().max(80).optional().default(''),

    motif: z.enum(['voyage', 'poche', 'reste']).default('voyage'),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Tranche invalide.' });
  const m = (await q('SELECT voyageur_id, statut FROM missions WHERE id = $1', [id])).rows[0];
  if (!m) return res.status(404).json({ error: 'Mission introuvable.' });
  if (m.statut === 'cloturee') {
    return res.status(409).json({ error: 'Mission clôturée — la compta passée ne se modifie pas.' });
  }
  const d = parsed.data;
  const taux = d.devise === 'DA' ? 1 : d.taux;
  if (!taux) return res.status(400).json({ error: 'Taux requis pour une devise étrangère.' });

  const { rows } = await q(
    `INSERT INTO tranches_devises (voyageur_id, mission_id, usd, taux, devise, source, motif)
     VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
    [m.voyageur_id, id, d.montant, taux, d.devise, d.source, d.motif]);
  if (d.motif === 'voyage') await majDouaneEstimee(id);
  const mc = (await q('SELECT code FROM missions WHERE id = $1', [id])).rows[0];
  await audit(req.user.sub, 'tranche', 'mission', id,
    { code: mc?.code, motif: d.motif, montant: d.montant, devise: d.devise, taux, source: d.source });
  res.status(201).json(rows[0]);
});

missionsRouter.delete('/:id/tranches/:tid', async (req, res) => {
  const id = Number(req.params.id);
  const cur = (await q('SELECT statut FROM missions WHERE id = $1', [id])).rows[0];
  if (!cur) return res.status(404).json({ error: 'Mission introuvable.' });
  if (cur.statut === 'cloturee') {
    return res.status(409).json({ error: 'Mission clôturée — la compta passée ne se modifie pas.' });
  }
  const del = (await q(
    'DELETE FROM tranches_devises WHERE id = $1 AND mission_id = $2 RETURNING motif',
    [Number(req.params.tid), id])).rows[0];
  if (del?.motif === 'voyage') await majDouaneEstimee(id);
  res.json({ ok: true });
});

missionsRouter.post('/:id/paiements', async (req, res) => {
  const id = Number(req.params.id);
  const parsed = z.object({
    montant: z.coerce.number().positive(),
    devise: z.enum(['DA', 'USD', 'EUR']).default('DA'),
    taux: z.coerce.number().positive().optional(),
    moyen: z.enum(['cash', 'en_ligne']).default('cash'),
    note: z.string().max(200).optional().default('versement dépôt'),
    chambre_id: z.coerce.number().int().optional(),
    date: z.string().max(10).optional(),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Montant invalide.' });
  const d = parsed.data;
  if (d.devise !== 'DA' && !(Number(d.taux) > 0)) {
    return res.status(400).json({ error: 'Taux requis pour un versement en devise.' });
  }
  const montantDA = d.devise === 'DA' ? d.montant : Math.round(d.montant * d.taux);
  const { rows } = await q(
    `INSERT INTO paiements (mission_id, montant, note, chambre_id, user_id, date,
       devise, taux, montant_devise, moyen)
     VALUES ($1,$2,$3,$4,$5,COALESCE($6, CURRENT_DATE),$7,$8,$9,$10) RETURNING *`,
    [id, montantDA, d.note, d.chambre_id ?? null, req.user.sub, d.date ?? null,
     d.devise, d.devise === 'DA' ? null : d.taux,
     d.devise === 'DA' ? null : d.montant, d.moyen]);
  const m = (await q('SELECT code FROM missions WHERE id = $1', [id])).rows[0];
  const ch = d.chambre_id
    ? (await q('SELECT nom FROM chambres WHERE id = $1', [d.chambre_id])).rows[0] : null;
  await audit(req.user.sub, 'encaissement', 'mission', id, {
    code: m?.code, montant: montantDA, moyen: d.moyen,
    ...(d.devise !== 'DA' ? { devise: d.devise, montant_devise: d.montant, taux: d.taux } : {}),
    ...(ch ? { depot: ch.nom } : {}),
  });
  res.status(201).json(rows[0]);
});

missionsRouter.delete('/:id/paiements/:pid', async (req, res) => {
  const id = Number(req.params.id);
  const del = (await q(
    'DELETE FROM paiements WHERE id = $1 AND mission_id = $2 RETURNING montant',
    [Number(req.params.pid), id])).rows[0];
  if (!del) return res.status(404).json({ error: 'Versement introuvable.' });
  await audit(req.user.sub, 'encaissement_annule', 'mission', id, { montant: Number(del.montant) });
  res.json({ ok: true });
});
