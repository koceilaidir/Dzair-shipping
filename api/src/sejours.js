import { Router } from 'express';
import { z } from 'zod';
import { q } from './db.js';
import { requireAuth, requireRole } from './auth.js';

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

async function membresDe(sejourId) {
  return (await q(`
    SELECT m.id, m.code, m.statut, v.nom, v.est_admin
    FROM missions m JOIN voyageurs v ON v.id = m.voyageur_id
    WHERE m.sejour_id = $1 AND m.statut <> 'annulee'
    ORDER BY v.est_admin DESC, v.nom`, [sejourId])).rows;
}

async function detailSejour(sejourId) {
  const s = (await q('SELECT * FROM sejours WHERE id = $1', [sejourId])).rows[0];
  if (!s) return null;
  const membres = await membresDe(sejourId);
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
    id: s.id, vol: s.vol, depart: s.depart, retour: s.retour, cloture: s.cloture,
    membres, depenses,
    total_da: Math.round(total),
    par_type: Object.fromEntries(
      Object.entries(parType).map(([k, v]) => [k, Math.round(v)])),
    nb_membres: membres.length,
    part: Math.round(total / Math.max(1, membres.length)),
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
           (SELECT COUNT(*) FROM missions m
            WHERE m.sejour_id = s.id AND m.statut <> 'annulee') AS nb_membres,
           (SELECT COALESCE(SUM(montant_da), 0) FROM depenses_sejour d
            WHERE d.sejour_id = s.id) AS total_da
    FROM sejours s ORDER BY s.depart DESC NULLS LAST, s.id DESC LIMIT 60`);
  res.json(rows.map((s) => ({
    id: s.id, vol: s.vol, depart: s.depart, retour: s.retour, cloture: s.cloture,
    nb_membres: Number(s.nb_membres), total_da: Math.round(Number(s.total_da)),
    part: Math.round(Number(s.total_da) / Math.max(1, Number(s.nb_membres))),
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
  if (!d) return res.status(404).json({ error: 'Séjour introuvable.' });
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
  if (!s) return res.status(404).json({ error: 'Séjour introuvable.' });
  if (s.cloture) {
    return res.status(409).json({ error: 'Séjour clôturé — les dépenses ne bougent plus.' });
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
    return res.status(409).json({ error: 'Séjour clôturé — les dépenses ne bougent plus.' });
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
