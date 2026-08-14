import { Router } from 'express';
import { z } from 'zod';
import { q } from './db.js';
import { requireAuth, requireRole } from './auth.js';
import { getReglages } from './reglages.js';

export const missionsRouter = Router();
missionsRouter.use(requireAuth, requireRole('admin'));

/* ---------- Schémas ---------- */
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

const frais = (m) =>
  Number(m.billet) + Number(m.dem_cout) + Number(m.jours) * Number(m.budget_jour) +
  Number(m.bea) + Number(m.douane) + Number(m.autres);

const moisDe = (d) => (d || new Date().toISOString().slice(0, 10)).slice(0, 7);

/* ---------- Liste ---------- */
missionsRouter.get('/', async (_req, res) => {
  const { rows } = await q(`
    SELECT m.*, v.nom AS voyageur_nom,
           COALESCE(SUM(p.kg), 0)            AS kg_total,
           COALESCE(SUM(p.kg * p.prix_kg), 0) AS revenu
    FROM missions m
    JOIN voyageurs v ON v.id = m.voyageur_id
    LEFT JOIN produits_mission p ON p.mission_id = m.id
    WHERE m.statut <> 'annulee'
    GROUP BY m.id, v.nom
    ORDER BY m.depart DESC NULLS LAST, m.id DESC
  `);
  res.json(rows);
});

/* ---------- Détail ---------- */
missionsRouter.get('/:id', async (req, res) => {
  const id = Number(req.params.id);
  const m = (await q(
    `SELECT m.*, v.nom AS voyageur_nom, v.comm_mode AS v_comm_mode,
            v.comm_val AS v_comm_val, v.bagages AS v_bagages
     FROM missions m JOIN voyageurs v ON v.id = m.voyageur_id WHERE m.id = $1`,
    [id])).rows[0];
  if (!m) return res.status(404).json({ error: 'Mission introuvable.' });
  const produits = (await q(
    'SELECT * FROM produits_mission WHERE mission_id = $1 ORDER BY id', [id])).rows;
  const paiements = (await q(
    'SELECT * FROM paiements WHERE mission_id = $1 ORDER BY date, id', [id])).rows;
  const tranches = (await q(
    'SELECT * FROM tranches_devises WHERE mission_id = $1 ORDER BY id', [id])).rows;
  res.json({ ...m, produits, paiements, tranches });
});

/* ---------- Création multi-voyageurs : un vol, N missions ---------- */
missionsRouter.post('/', async (req, res) => {
  const parsed = missionBase.extend({
    voyageur_ids: z.array(z.coerce.number().int()).min(1),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Données invalides.' });
  const { voyageur_ids, ...base } = parsed.data;
  const mois = moisDe(base.depart);
  const reglages = await getReglages();

  // Démarches : prix par défaut des réglages selon le type (modifiable ensuite sur la fiche).
  if (!base.dem_cout) {
    base.dem_cout = {
      premiere: reglages.prix_premiere,
      renouvellement: reglages.prix_renouvellement,
      visa_double: reglages.prix_visa_double,
      multiple: 0,
    }[base.dem_type] ?? 0;
  }

  // Garde-fous : 2 missions/mois max + documents valides à la date du RETOUR (douane au retour).
  const dateRef = base.retour || base.depart || new Date().toISOString().slice(0, 10);
  const bloques = [];
  for (const vid of voyageur_ids) {
    const { rows } = await q(
      `SELECT v.nom, v.passeport_expire, v.autorisation_expire, COUNT(m.id) AS n
       FROM voyageurs v
       LEFT JOIN missions m ON m.voyageur_id = v.id
         AND m.statut <> 'annulee' AND to_char(m.depart, 'YYYY-MM') = $2
       WHERE v.id = $1 GROUP BY v.id`, [vid, mois]);
    const r = rows[0];
    if (!r) return res.status(400).json({ error: `Voyageur ${vid} introuvable.` });
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
    const kgSoute = (Number(v.bagages) || 2) * 23; // paramètre valises du voyageur
    const seq = (await q('SELECT COUNT(*) AS n FROM missions')).rows[0].n;
    const code = 'MSN-' + String(Number(seq) + 1).padStart(3, '0');
    const { rows } = await q(
      `INSERT INTO missions (voyageur_id, code, vol, depart, retour, jours, budget_jour,
         billet, dem_type, dem_cout, bea, douane, autres, objectif, kg_soute, val_declaree, statut)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,'encours') RETURNING *`,
      [vid, code, base.vol, base.depart, base.retour, base.jours, base.budget_jour,
       base.billet, base.dem_type, base.dem_cout, base.bea, base.douane, base.autres,
       base.objectif, kgSoute, base.val_declaree ?? null]);
    created.push(rows[0]);
    await q(`INSERT INTO audit_log (user_id, action, entite, entite_id, details)
             VALUES ($1,'create','mission',$2,$3)`,
      [req.user.sub, rows[0].id, JSON.stringify({ code, voyageur: v.nom })]);
  }
  res.status(201).json(created);
});

/* ---------- Mise à jour (frais / statut) ---------- */
missionsRouter.put('/:id', async (req, res) => {
  const id = Number(req.params.id);
  const parsed = missionBase.partial().extend({
    statut: z.enum(['planifiee', 'encours', 'annulee']).optional(),
    cabine: z.boolean().optional(),
    kg_soute: z.coerce.number().positive().optional(),
    check_depart: z.record(z.string(), z.boolean()).optional(),
    check_retour: z.record(z.string(), z.boolean()).optional(),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Données invalides.' });

  const cur = (await q('SELECT * FROM missions WHERE id = $1', [id])).rows[0];
  if (!cur) return res.status(404).json({ error: 'Mission introuvable.' });
  if (cur.statut === 'cloturee') {
    return res.status(409).json({ error: 'Mission clôturée — la compta passée ne se modifie pas.' });
  }
  const m = { ...cur, ...parsed.data };
  const { rows } = await q(
    `UPDATE missions SET vol=$1, depart=$2, retour=$3, jours=$4, budget_jour=$5, billet=$6,
       dem_type=$7, dem_cout=$8, bea=$9, douane=$10, autres=$11, objectif=$12,
       kg_soute=$13, cabine=$14, val_declaree=$15, statut=$16,
       check_depart=$17, check_retour=$18
     WHERE id=$19 RETURNING *`,
    [m.vol, m.depart, m.retour, m.jours, m.budget_jour, m.billet, m.dem_type, m.dem_cout,
     m.bea, m.douane, m.autres, m.objectif, m.kg_soute, m.cabine, m.val_declaree, m.statut,
     JSON.stringify(m.check_depart ?? {}), JSON.stringify(m.check_retour ?? {}), id]);
  res.json(rows[0]);
});

/* ---------- Valise ---------- */
missionsRouter.post('/:id/produits', async (req, res) => {
  const id = Number(req.params.id);
  const parsed = z.object({
    nom: z.string().min(1).max(160),
    kg: z.coerce.number().positive(),
    prix_kg: z.coerce.number().positive(),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Produit invalide.' });
  const cur = (await q('SELECT statut FROM missions WHERE id = $1', [id])).rows[0];
  if (!cur) return res.status(404).json({ error: 'Mission introuvable.' });
  if (cur.statut === 'cloturee') {
    return res.status(409).json({ error: 'Valise clôturée — on n’y touche plus.' });
  }
  const { rows } = await q(
    `INSERT INTO produits_mission (mission_id, nom, kg, prix_kg)
     VALUES ($1,$2,$3,$4) RETURNING *`,
    [id, parsed.data.nom, parsed.data.kg, parsed.data.prix_kg]);
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

/* ---------- Clôture : fige la commission du voyageur ---------- */
missionsRouter.post('/:id/cloture', async (req, res) => {
  const id = Number(req.params.id);
  const parsed = z.object({
    depot: z.string().max(120).optional().default(''),
    attendu: z.coerce.number().nonnegative(),
    encaisse: z.coerce.number().nonnegative().default(0),
    primes: z.coerce.number().nonnegative().default(0),
    invendus: z.string().max(1000).optional().default(''),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Données invalides.' });

  const m = (await q(
    `SELECT m.*, v.comm_mode AS v_mode, v.comm_val AS v_val
     FROM missions m JOIN voyageurs v ON v.id = m.voyageur_id WHERE m.id = $1`,
    [id])).rows[0];
  if (!m) return res.status(404).json({ error: 'Mission introuvable.' });
  if (m.statut === 'cloturee') return res.status(409).json({ error: 'Déjà clôturée.' });

  const kg = Number((await q(
    'SELECT COALESCE(SUM(kg),0) AS kg FROM produits_mission WHERE mission_id = $1',
    [id])).rows[0].kg);
  const d = parsed.data;
  const benefice = d.attendu - frais(m);
  // La commission appliquée est celle du voyageur AU MOMENT de la clôture — figée à vie.
  const commission =
    m.v_mode === 'kg' ? Number(m.v_val) * kg :
    m.v_mode === 'pct' ? Math.max(0, benefice) * Number(m.v_val) / 100 :
    Number(m.v_val);

  const { rows } = await q(
    `UPDATE missions SET statut='cloturee', depot=$1, attendu=$2, primes=$3, invendus=$4,
       cloture_date=CURRENT_DATE, comm_mode=$5, comm_val=$6, commission=$7
     WHERE id=$8 RETURNING *`,
    [d.depot, d.attendu, d.primes, d.invendus, m.v_mode, m.v_val, commission, id]);
  if (d.encaisse > 0) {
    await q(`INSERT INTO paiements (mission_id, montant, note)
             VALUES ($1,$2,'encaissement clôture')`, [id, d.encaisse]);
  }
  await q(`INSERT INTO audit_log (user_id, action, entite, entite_id, details)
           VALUES ($1,'cloture','mission',$2,$3)`,
    [req.user.sub, id, JSON.stringify({ attendu: d.attendu, commission })]);
  res.json(rows[0]);
});

/* ---------- Devises déposées (tranches multi-monnaies) ---------- */
missionsRouter.post('/:id/tranches', async (req, res) => {
  const id = Number(req.params.id);
  const parsed = z.object({
    montant: z.coerce.number().positive(),           // dans la devise choisie
    devise: z.enum(['USD', 'EUR', 'RMB']).default('USD'),
    taux: z.coerce.number().positive(),              // DA pour 1 unité de la devise
    source: z.string().max(80).optional().default(''),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Tranche invalide.' });
  const m = (await q('SELECT voyageur_id FROM missions WHERE id = $1', [id])).rows[0];
  if (!m) return res.status(404).json({ error: 'Mission introuvable.' });
  const d = parsed.data;
  // NB : la colonne `usd` porte le montant quelle que soit la devise (nom historique).
  const { rows } = await q(
    `INSERT INTO tranches_devises (voyageur_id, mission_id, usd, taux, devise, source)
     VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
    [m.voyageur_id, id, d.montant, d.taux, d.devise, d.source]);
  res.status(201).json(rows[0]);
});

missionsRouter.delete('/:id/tranches/:tid', async (req, res) => {
  await q('DELETE FROM tranches_devises WHERE id = $1 AND mission_id = $2',
    [Number(req.params.tid), Number(req.params.id)]);
  res.json({ ok: true });
});

/* ---------- Paiements (créances) ---------- */
missionsRouter.post('/:id/paiements', async (req, res) => {
  const id = Number(req.params.id);
  const parsed = z.object({
    montant: z.coerce.number().positive(),
    note: z.string().max(200).optional().default('versement dépôt'),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Montant invalide.' });
  const { rows } = await q(
    `INSERT INTO paiements (mission_id, montant, note) VALUES ($1,$2,$3) RETURNING *`,
    [id, parsed.data.montant, parsed.data.note]);
  res.status(201).json(rows[0]);
});
