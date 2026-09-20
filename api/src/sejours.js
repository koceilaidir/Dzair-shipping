import { Router } from 'express';
import { z } from 'zod';
import { q } from './db.js';
import { requireAuth } from './auth.js';
import { getReglages } from './reglages.js';
import {
  SQL_NON_DECLARE, fraisMission, capaciteMission, douaneMission, taxesCarteMission,
} from './compta.js';

export const SQL_PART_SEJOUR = `
  COALESCE(m.part_sejour, (
    SELECT COALESCE(SUM(d.montant_da), 0) / GREATEST(1, (
      SELECT COUNT(*) FROM missions mm
      WHERE mm.sejour_id = m.sejour_id AND mm.statut <> 'annulee'))
    FROM depenses_sejour d WHERE d.sejour_id = m.sejour_id
  ), 0)`;

export async function partSejourDe(missionId) {
  const r = (await q(
    `SELECT ${SQL_PART_SEJOUR} AS part FROM missions m WHERE m.id = $1`, [missionId])).rows[0];
  return Math.round(Number(r?.part ?? 0));
}

export async function figerPartSejour(missionId) {
  const part = await partSejourDe(missionId);
  await q('UPDATE missions SET part_sejour = $1 WHERE id = $2', [part, missionId]);
  return part;
}

const SQL_PASSAGERS = `
  SELECT m.*, v.nom AS voyageur_nom, v.devise_compte, v.est_admin, v.sans_carte,
         ${SQL_NON_DECLARE} AS non_declare,
         ${SQL_PART_SEJOUR} AS part_sejour_calc,
         COALESCE((SELECT SUM(kg) FROM produits_mission p WHERE p.mission_id = m.id), 0)
           + COALESCE((SELECT SUM(a.quantite * l.poids_total / l.quantite)
                       FROM affectations a JOIN bon_lignes l ON l.id = a.ligne_id
                       WHERE a.mission_id = m.id), 0)                        AS kg_total,
         COALESCE((SELECT SUM(kg * prix_kg) FROM produits_mission p WHERE p.mission_id = m.id), 0)
           + COALESCE((SELECT SUM((a.quantite - COALESCE(a.saisis, 0)) * CASE WHEN l.mode = 'kg'
                                   THEN l.prix * l.poids_total / l.quantite ELSE l.prix END)
                       FROM affectations a JOIN bon_lignes l ON l.id = a.ligne_id
                       WHERE a.mission_id = m.id), 0)                        AS revenu,
         COALESCE((SELECT SUM(usd) FROM tranches_devises t
                   WHERE t.mission_id = m.id AND t.motif = 'voyage'), 0)     AS marchandise_devise,
         COALESCE((SELECT SUM(usd * taux) FROM tranches_devises t
                   WHERE t.mission_id = m.id AND t.motif = 'voyage'), 0)     AS marchandise_da,
         COALESCE((SELECT SUM(usd * taux) FROM tranches_devises t
                   WHERE t.mission_id = m.id AND t.motif = 'poche'), 0)      AS poche_da,
         COALESCE((SELECT SUM(usd * taux) FROM tranches_devises t
                   WHERE t.mission_id = m.id AND t.motif = 'reste'), 0)      AS reste_da,
         COALESCE((SELECT SUM(a.quantite * COALESCE(a.prix_declare, 0))
                   FROM affectations a WHERE a.mission_id = m.id
                     AND a.emplacement = 'soute'), 0)                        AS declare_total
  FROM missions m JOIN voyageurs v ON v.id = m.voyageur_id
  WHERE m.sejour_id = ANY($1) AND m.statut <> 'annulee'
  ORDER BY v.est_admin DESC, v.nom`;

function passagerCompta(r, reglages) {
  const douane = douaneMission(r, reglages);
  const taxesCarte = taxesCarteMission(r, reglages);
  const part = Math.round(Number(r.part_sejour_calc || 0));
  const frais = fraisMission(
    { ...r, douane, part_sejour_calc: part },
    Number(r.poche_da), taxesCarte, Number(r.reste_da));
  const capacite = capaciteMission(r);
  const kg = Number(r.kg_total);
  const revenu = r.statut === 'cloturee' ? Number(r.attendu ?? 0) : Number(r.revenu);
  return {
    id: r.id, sejour_id: r.sejour_id, code: r.code, statut: r.statut,
    voyageur_id: r.voyageur_id, voyageur_nom: r.voyageur_nom,
    est_admin: !!r.est_admin, sans_carte: !!r.sans_carte, non_declare: !!r.non_declare,
    depart: r.depart, retour: r.retour, jours: r.jours,
    valise_close: r.valise_close, bagage_main: r.bagage_main,
    kg_total: Math.round(kg * 10) / 10,
    capacite: Math.round(capacite * 10) / 10,
    kg_libres: Math.round(Math.max(0, capacite - kg) * 10) / 10,
    revenu: Math.round(revenu),
    frais: Math.round(frais),
    douane: Math.round(douane),
    taxes_carte: Math.round(taxesCarte),
    part_sejour_da: part,
    objectif: Math.round(Number(r.objectif)),
    benefice: Math.round(revenu - frais),
    commission: r.commission == null ? null : Math.round(Number(r.commission)),
  };
}

async function passagersParSejour(sejourIds, reglages) {
  const parSejour = new Map(sejourIds.map((id) => [id, []]));
  if (!sejourIds.length) return parSejour;
  const { rows } = await q(SQL_PASSAGERS, [sejourIds]);
  for (const r of rows) {
    parSejour.get(r.sejour_id)?.push(passagerCompta(r, reglages));
  }
  return parSejour;
}

function resumeSejour(s, passagers, depenses) {
  const total = (k) => passagers.reduce((t, p) => t + p[k], 0);
  const kg = total('kg_total'), capacite = total('capacite');
  const aCouvrir = Math.max(0, total('frais') + total('objectif') - total('revenu'));
  const kgLibres = Math.max(0, capacite - kg);
  const tousClos = passagers.length > 0 && passagers.every((p) => p.statut === 'cloturee');
  const partie = passagers.some((p) => p.depart && String(p.depart).slice(0, 10)
    <= new Date().toISOString().slice(0, 10));
  return {
    id: s.id, vol: s.vol, depart: s.depart, retour: s.retour, cloture: s.cloture,
    nb_membres: passagers.length,
    etat: tousClos ? 'cloturee' : partie ? 'en_cours' : 'preparation',
    total_da: Math.round(depenses),
    part: Math.round(depenses / Math.max(1, passagers.length)),
    kg_total: Math.round(kg * 10) / 10,
    capacite: Math.round(capacite * 10) / 10,
    kg_libres: Math.round(kgLibres * 10) / 10,
    revenu: Math.round(total('revenu')),
    frais: Math.round(total('frais')),
    objectif: Math.round(total('objectif')),
    benefice: Math.round(total('revenu') - total('frais')),
    a_couvrir: Math.round(aCouvrir),
    seuil_kg: kgLibres > 0 ? Math.round(aCouvrir / kgLibres) : 0,
  };
}

async function membresDe(sejourId) {
  return (await q(`
    SELECT m.id, m.code, m.statut, v.nom, v.est_admin, v.sans_carte
    FROM missions m JOIN voyageurs v ON v.id = m.voyageur_id
    WHERE m.sejour_id = $1 AND m.statut <> 'annulee'
    ORDER BY v.est_admin DESC, v.nom`, [sejourId])).rows;
}

async function detailSejour(sejourId) {
  const s = (await q('SELECT * FROM sejours WHERE id = $1', [sejourId])).rows[0];
  if (!s) return null;
  const reglages = await getReglages();
  const passagers = (await passagersParSejour([sejourId], reglages)).get(sejourId) ?? [];
  const depenses = (await q(`
    SELECT d.*, u.nom AS paye_par_nom
    FROM depenses_sejour d LEFT JOIN users u ON u.id = d.paye_par
    WHERE d.sejour_id = $1 ORDER BY d.date DESC, d.id DESC`, [sejourId])).rows;
  const total = depenses.reduce((t, d) => t + Number(d.montant_da), 0);
  const parType = {};
  for (const d of depenses) {
    parType[d.type] = (parType[d.type] || 0) + Number(d.montant_da);
  }
  return {
    ...resumeSejour(s, passagers, total),
    passagers,
    membres: await membresDe(sejourId),
    depenses,
    par_type: Object.fromEntries(
      Object.entries(parType).map(([k, v]) => [k, Math.round(v)])),
  };
}

export const sejoursRouter = Router();
sejoursRouter.use(requireAuth);

const adminSeul = (req, res, next) =>
  req.user.role === 'admin' ? next()
    : res.status(403).json({ error: 'Réservé aux admins.' });

sejoursRouter.get('/', adminSeul, async (_req, res) => {
  const { rows } = await q(`
    SELECT s.*,
           (SELECT COALESCE(SUM(montant_da), 0) FROM depenses_sejour d
            WHERE d.sejour_id = s.id) AS total_da
    FROM sejours s
    WHERE EXISTS (SELECT 1 FROM missions m
                  WHERE m.sejour_id = s.id AND m.statut <> 'annulee')
    ORDER BY s.depart DESC NULLS LAST, s.id DESC LIMIT 60`);
  const reglages = await getReglages();
  const parSejour = await passagersParSejour(rows.map((s) => s.id), reglages);
  res.json(rows.map((s) => ({
    ...resumeSejour(s, parSejour.get(s.id) ?? [], Number(s.total_da)),
    passagers: (parSejour.get(s.id) ?? []).map((p) => ({
      id: p.id, voyageur_nom: p.voyageur_nom,
      est_admin: p.est_admin, sans_carte: p.sans_carte,
    })),
  })));
});

sejoursRouter.get('/en-cours', adminSeul, async (_req, res) => {
  const s = (await q(`
    SELECT s.id FROM sejours s
    WHERE EXISTS (SELECT 1 FROM missions m
                  WHERE m.sejour_id = s.id AND m.statut NOT IN ('annulee', 'cloturee'))
    ORDER BY s.depart DESC NULLS LAST, s.id DESC LIMIT 1`)).rows[0];
  if (!s) return res.json(null);
  res.json(await detailSejour(s.id));
});

sejoursRouter.get('/:id', adminSeul, async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return res.status(400).json({ error: 'Identifiant invalide.' });
  const d = await detailSejour(id);
  if (!d) return res.status(404).json({ error: 'Mission introuvable.' });
  res.json(d);
});

const depenseSchema = z.object({
  type: z.enum(['hotel', 'nourriture', 'transport', 'autre']).default('autre'),
  montant: z.coerce.number().positive(),
  devise: z.enum(['RMB', 'USD', 'EUR', 'DA']).default('DA'),
  taux: z.coerce.number().positive().optional(),
  moyen: z.enum(['alipay', 'cash']).default('cash'),
  paye_par: z.coerce.number().int().optional(),
  note: z.string().max(300).optional().default(''),
  date: z.string().max(10).optional(),
});

sejoursRouter.post('/:id/depenses', adminSeul, async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return res.status(400).json({ error: 'Identifiant invalide.' });
  const parsed = depenseSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Dépense invalide.' });
  const d = parsed.data;
  if (d.devise !== 'DA' && !(Number(d.taux) > 0)) {
    return res.status(400).json({ error: 'Taux requis pour une devise étrangère.' });
  }
  const s = (await q('SELECT cloture FROM sejours WHERE id = $1', [id])).rows[0];
  if (!s) return res.status(404).json({ error: 'Mission introuvable.' });
  if (s.cloture) {
    return res.status(409).json({ error: 'Mission clôturée — les dépenses ne bougent plus.' });
  }
  const taux = d.devise === 'DA' ? 1 : Number(d.taux);
  const montantDA = Math.round(d.montant * taux);
  const { rows } = await q(
    `INSERT INTO depenses_sejour
       (sejour_id, type, montant, devise, taux, montant_da, moyen, paye_par, note, date, user_id)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,COALESCE($10, CURRENT_DATE),$11) RETURNING *`,
    [id, d.type, d.montant, d.devise, taux, montantDA, d.moyen,
     d.paye_par ?? req.user.sub, d.note, d.date || null, req.user.sub]);
  await q(`INSERT INTO audit_log (user_id, action, entite, entite_id, details)
           VALUES ($1,'depense','sejour',$2,$3)`,
    [req.user.sub, id, JSON.stringify({
      type: d.type, montant_da: montantDA, devise: d.devise, moyen: d.moyen })]);
  res.status(201).json(rows[0]);
});

sejoursRouter.delete('/:id/depenses/:did', adminSeul, async (req, res) => {
  const id = Number(req.params.id), did = Number(req.params.did);
  if (!Number.isInteger(id) || !Number.isInteger(did)) {
    return res.status(400).json({ error: 'Identifiant invalide.' });
  }
  const s = (await q('SELECT cloture FROM sejours WHERE id = $1', [id])).rows[0];
  if (s?.cloture) {
    return res.status(409).json({ error: 'Mission clôturée — les dépenses ne bougent plus.' });
  }
  const r = await q(
    'DELETE FROM depenses_sejour WHERE id = $1 AND sejour_id = $2 RETURNING montant_da, type',
    [did, id]);
  if (!r.rows[0]) return res.status(404).json({ error: 'Dépense introuvable.' });
  await q(`INSERT INTO audit_log (user_id, action, entite, entite_id, details)
           VALUES ($1,'depense_suppr','sejour',$2,$3)`,
    [req.user.sub, id, JSON.stringify({
      type: r.rows[0].type, montant_da: Number(r.rows[0].montant_da) })]);
  res.json({ ok: true });
});
