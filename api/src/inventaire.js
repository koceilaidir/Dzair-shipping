import { Router } from 'express';
import { z } from 'zod';
import { q } from './db.js';
import { requireAuth, requireRole } from './auth.js';

/* Chambres (grossistes en Chine + dépôt en Algérie), bons de récupération,
   inventaire (stock à l'hôtel) et affectations produit → valise d'une mission. */
export const inventaireRouter = Router();
inventaireRouter.use(requireAuth, requireRole('admin'));

const audit = (userId, action, entite, id, details) => q(
  `INSERT INTO audit_log (user_id, action, entite, entite_id, details) VALUES ($1,$2,$3,$4,$5)`,
  [userId, action, entite, id, JSON.stringify(details)]);

/* ================= CHAMBRES ================= */
const contactSchema = z.object({
  nom: z.string().min(1).max(120),
  tel: z.string().max(40).optional().default(''),
  role: z.string().max(40).optional().default(''),
});
const chambreSchema = z.object({
  nom: z.string().min(1).max(120),
  ville: z.string().max(80).optional().default('Canton'),
  depot_adresse: z.string().max(300).optional().default(''),
  depot_wilaya: z.string().max(80).optional().default(''),
  note: z.string().max(1000).optional().default(''),
  contacts: z.array(contactSchema).optional().default([]),
});

async function chambreComplete(id) {
  const c = (await q('SELECT * FROM chambres WHERE id = $1', [id])).rows[0];
  if (!c) return null;
  c.contacts = (await q('SELECT * FROM chambre_contacts WHERE chambre_id = $1 ORDER BY id', [id])).rows;
  c.bons = (await q(
    `SELECT b.*,
            COALESCE(SUM(l.poids_total),0) AS kg,
            COALESCE(SUM(l.quantite),0)    AS pieces,
            COALESCE(SUM(CASE WHEN l.mode='kg' THEN l.poids_total*l.prix ELSE l.quantite*l.prix END),0) AS gain_da
     FROM bons b LEFT JOIN bon_lignes l ON l.bon_id = b.id
     WHERE b.chambre_id = $1 GROUP BY b.id ORDER BY b.date DESC, b.id DESC`, [id])).rows;
  return c;
}

inventaireRouter.get('/chambres', async (_req, res) => {
  const { rows } = await q(`
    SELECT c.*,
           (SELECT COUNT(*) FROM bons b WHERE b.chambre_id = c.id)      AS nb_bons,
           (SELECT MAX(date) FROM bons b WHERE b.chambre_id = c.id)     AS dernier_bon,
           (SELECT COALESCE(json_agg(json_build_object('id',k.id,'nom',k.nom,'tel',k.tel,'role',k.role) ORDER BY k.id),'[]')
              FROM chambre_contacts k WHERE k.chambre_id = c.id)        AS contacts
    FROM chambres c ORDER BY c.nom`);
  res.json(rows);
});

inventaireRouter.get('/chambres/:id', async (req, res) => {
  const c = await chambreComplete(Number(req.params.id));
  if (!c) return res.status(404).json({ error: 'Chambre introuvable.' });
  res.json(c);
});

inventaireRouter.post('/chambres', async (req, res) => {
  const p = chambreSchema.safeParse(req.body);
  if (!p.success) return res.status(400).json({ error: 'Données invalides.' });
  const d = p.data;
  const c = (await q(
    `INSERT INTO chambres (nom, ville, depot_adresse, depot_wilaya, note)
     VALUES ($1,$2,$3,$4,$5) RETURNING *`,
    [d.nom, d.ville, d.depot_adresse, d.depot_wilaya, d.note])).rows[0];
  for (const k of d.contacts) {
    await q('INSERT INTO chambre_contacts (chambre_id, nom, tel, role) VALUES ($1,$2,$3,$4)',
      [c.id, k.nom, k.tel, k.role]);
  }
  await audit(req.user.sub, 'create', 'chambre', c.id, { nom: d.nom });
  res.status(201).json(await chambreComplete(c.id));
});

inventaireRouter.put('/chambres/:id', async (req, res) => {
  const id = Number(req.params.id);
  const p = chambreSchema.safeParse(req.body);
  if (!p.success) return res.status(400).json({ error: 'Données invalides.' });
  const d = p.data;
  const r = await q(
    `UPDATE chambres SET nom=$1, ville=$2, depot_adresse=$3, depot_wilaya=$4, note=$5
     WHERE id=$6 RETURNING id`, [d.nom, d.ville, d.depot_adresse, d.depot_wilaya, d.note, id]);
  if (!r.rows[0]) return res.status(404).json({ error: 'Chambre introuvable.' });
  // Contacts : on remplace la liste entière (simple et sûr).
  await q('DELETE FROM chambre_contacts WHERE chambre_id = $1', [id]);
  for (const k of d.contacts) {
    await q('INSERT INTO chambre_contacts (chambre_id, nom, tel, role) VALUES ($1,$2,$3,$4)',
      [id, k.nom, k.tel, k.role]);
  }
  await audit(req.user.sub, 'update', 'chambre', id, { nom: d.nom });
  res.json(await chambreComplete(id));
});

inventaireRouter.delete('/chambres/:id', async (req, res) => {
  const id = Number(req.params.id);
  const n = Number((await q('SELECT COUNT(*) AS n FROM bons WHERE chambre_id = $1', [id])).rows[0].n);
  if (n > 0) return res.status(409).json({ error: 'Cette chambre a des bons — on garde son historique.' });
  const r = await q('DELETE FROM chambres WHERE id = $1 RETURNING nom', [id]);
  if (!r.rows[0]) return res.status(404).json({ error: 'Chambre introuvable.' });
  await audit(req.user.sub, 'delete', 'chambre', id, { nom: r.rows[0].nom });
  res.json({ ok: true });
});

/* ================= BONS ================= */
const ligneSchema = z.object({
  produit: z.string().min(1).max(160),
  quantite: z.coerce.number().positive(),
  poids_total: z.coerce.number().positive(),
  manque_rmb: z.coerce.number().nonnegative().default(0),
  mode: z.enum(['kg', 'piece']).default('kg'),
  prix: z.coerce.number().nonnegative().default(0),
});
const bonSchema = z.object({
  chambre_id: z.coerce.number().int(),
  date: z.string().max(10).optional(),
  note: z.string().max(1000).optional().default(''),
  lignes: z.array(ligneSchema).min(1),
});

inventaireRouter.post('/bons', async (req, res) => {
  const p = bonSchema.safeParse(req.body);
  if (!p.success) return res.status(400).json({ error: 'Bon invalide (au moins une ligne).' });
  const d = p.data;
  const ch = (await q('SELECT nom FROM chambres WHERE id = $1', [d.chambre_id])).rows[0];
  if (!ch) return res.status(404).json({ error: 'Chambre introuvable.' });
  const b = (await q(
    `INSERT INTO bons (chambre_id, date, note, user_id) VALUES ($1, COALESCE($2, CURRENT_DATE), $3, $4)
     RETURNING *`, [d.chambre_id, d.date ?? null, d.note, req.user.sub])).rows[0];
  for (const l of d.lignes) {
    await q(
      `INSERT INTO bon_lignes (bon_id, produit, quantite, poids_total, manque_rmb, mode, prix)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [b.id, l.produit, l.quantite, l.poids_total, l.manque_rmb, l.mode, l.prix]);
  }
  const kg = d.lignes.reduce((t, l) => t + l.poids_total, 0);
  const da = d.lignes.reduce((t, l) => t + (l.mode === 'kg' ? l.prix * l.poids_total : l.prix * l.quantite), 0);
  await audit(req.user.sub, 'create', 'bon', b.id, {
    chambre: ch.nom, lignes: d.lignes.length, kg: Math.round(kg * 10) / 10, da: Math.round(da),
    produits: d.lignes.slice(0, 4).map((l) => l.produit),
  });
  res.status(201).json(b);
});

inventaireRouter.get('/bons/:id', async (req, res) => {
  const id = Number(req.params.id);
  const b = (await q(
    `SELECT b.*, c.nom AS chambre_nom FROM bons b JOIN chambres c ON c.id = b.chambre_id WHERE b.id = $1`,
    [id])).rows[0];
  if (!b) return res.status(404).json({ error: 'Bon introuvable.' });
  b.lignes = (await q(
    `SELECT l.*, COALESCE(SUM(a.quantite),0) AS affecte
     FROM bon_lignes l LEFT JOIN affectations a ON a.ligne_id = l.id
     WHERE l.bon_id = $1 GROUP BY l.id ORDER BY l.id`, [id])).rows;
  res.json(b);
});

inventaireRouter.delete('/bons/:id', async (req, res) => {
  const id = Number(req.params.id);
  const n = Number((await q(
    `SELECT COUNT(*) AS n FROM affectations a JOIN bon_lignes l ON l.id = a.ligne_id WHERE l.bon_id = $1`,
    [id])).rows[0].n);
  if (n > 0) return res.status(409).json({ error: 'Des produits de ce bon sont déjà dans des valises.' });
  const b = (await q(
    `SELECT b.date, c.nom FROM bons b JOIN chambres c ON c.id = b.chambre_id WHERE b.id = $1`, [id])).rows[0];
  await q('DELETE FROM bons WHERE id = $1', [id]);
  await audit(req.user.sub, 'delete', 'bon', id, { chambre: b?.nom, date: b?.date });
  res.json({ ok: true });
});

/* ================= STOCK (inventaire) =================
   Chaque ligne avec son restant (quantité − affectée), son poids/unité, son gain
   DA/pièce et DA/kg. ?mission=ID ajoute les « concurrents » du même séjour
   (missions en cours dont les dates se chevauchent) pour la suggestion équitable. */
const gainPiece = (l) => l.mode === 'kg'
  ? Number(l.prix) * Number(l.poids_total) / Number(l.quantite)
  : Number(l.prix);

async function stockLignes() {
  // affecte     = pièces mises dans des valises (toutes missions)
  // en_cours    = pièces dans des valises de missions NON clôturées → encore exposées
  // livre       = pièces de missions clôturées (dépôt payé, plus en jeu)
  const { rows } = await q(`
    SELECT l.*, b.date AS bon_date, b.chambre_id, c.nom AS chambre_nom,
           COALESCE(SUM(a.quantite),0) AS affecte,
           COALESCE(SUM(a.quantite) FILTER (WHERE m.statut <> 'cloturee'),0) AS en_cours,
           COALESCE(SUM(a.quantite) FILTER (WHERE m.statut = 'cloturee'),0)  AS livre
    FROM bon_lignes l
    JOIN bons b ON b.id = l.bon_id
    JOIN chambres c ON c.id = b.chambre_id
    LEFT JOIN affectations a ON a.ligne_id = l.id
    LEFT JOIN missions m ON m.id = a.mission_id
    GROUP BY l.id, b.date, b.chambre_id, c.nom
    ORDER BY b.date DESC, l.id`);
  return rows.map((l) => {
    const restant = Number(l.quantite) - Number(l.affecte);
    const enCours = Number(l.en_cours);
    const poidsUnit = Number(l.poids_total) / Number(l.quantite);
    const gp = gainPiece(l);
    return {
      ...l,
      restant,                        // à l'hôtel, pas encore en valise
      en_cours: enCours,              // en valise, mission pas clôturée
      livre: Number(l.livre),
      expose: restant + enCours,      // tout ce qui est encore en jeu
      poids_unit: poidsUnit,
      kg_restant: restant * poidsUnit,
      kg_en_cours: enCours * poidsUnit,
      gain_piece: gp,
      gain_kg: poidsUnit > 0 ? gp / poidsUnit : 0,
      gain_restant: restant * gp,
      gain_en_cours: enCours * gp,
    };
  });
}

inventaireRouter.get('/stock', async (req, res) => {
  const lignes = await stockLignes();
  const out = { lignes, concurrents: [] };
  const mid = Number(req.query.mission);
  if (mid) {
    const me = (await q('SELECT depart, retour FROM missions WHERE id = $1', [mid])).rows[0];
    if (me) {
      // Même séjour = en cours, valise pas encore complète, dates qui se chevauchent
      // (pas forcément le même vol). Pour chacun : ce qui lui manque et ses kg dispo.
      const { rows } = await q(`
        SELECT m.id, m.code, m.objectif, m.kg_soute, m.cabine, m.billet, m.dem_cout, m.frais_visa,
               m.jours, m.budget_jour, m.douane, m.autres, v.nom AS voyageur,
               COALESCE((SELECT SUM(kg) FROM produits_mission p WHERE p.mission_id = m.id),0) AS kg_libre,
               COALESCE((SELECT SUM(kg*prix_kg) FROM produits_mission p WHERE p.mission_id = m.id),0) AS rev_libre
        FROM missions m JOIN voyageurs v ON v.id = m.voyageur_id
        WHERE m.id <> $1 AND m.statut = 'encours' AND m.valise_close = FALSE
          AND m.depart IS NOT NULL AND m.retour IS NOT NULL
          AND m.depart <= $3 AND m.retour >= $2`,
        [mid, me.depart, me.retour]);
      for (const m of rows) {
        const aff = (await q(
          `SELECT a.quantite, l.mode, l.prix, l.poids_total, l.quantite AS q_ligne
           FROM affectations a JOIN bon_lignes l ON l.id = a.ligne_id WHERE a.mission_id = $1`,
          [m.id])).rows;
        let kg = Number(m.kg_libre), rev = Number(m.rev_libre);
        for (const a of aff) {
          const pu = Number(a.poids_total) / Number(a.q_ligne);
          kg += Number(a.quantite) * pu;
          rev += Number(a.quantite) * gainPiece(a);
        }
        // Frais approximatifs (poche prévisionnelle) — suffisant pour l'équité.
        const frais = Number(m.billet) + Number(m.dem_cout) + Number(m.frais_visa || 0) +
          Number(m.jours) * Number(m.budget_jour) + Number(m.douane) + Number(m.autres);
        const cap = Number(m.kg_soute) + (m.cabine ? 10 : 0);
        out.concurrents.push({
          mission_id: m.id, code: m.code, voyageur: m.voyageur,
          manque_da: Math.max(0, Number(m.objectif) - (rev - frais)),
          kg_dispo: Math.max(0, cap - kg),
        });
      }
    }
  }
  res.json(out);
});

/* ================= TRAÇABILITÉ d'une ligne =================
   D'où vient chaque pièce (chambre, bon, prix, manque) et qui l'a descendue
   (voyageur, mission, statut, pièces, manquants). */
inventaireRouter.get('/lignes/:id', async (req, res) => {
  const id = Number(req.params.id);
  const l = (await q(
    `SELECT l.*, b.date AS bon_date, b.note AS bon_note, c.id AS chambre_id, c.nom AS chambre_nom,
            c.depot_wilaya, c.depot_adresse
     FROM bon_lignes l JOIN bons b ON b.id = l.bon_id JOIN chambres c ON c.id = b.chambre_id
     WHERE l.id = $1`, [id])).rows[0];
  if (!l) return res.status(404).json({ error: 'Produit introuvable.' });
  const traces = (await q(
    `SELECT a.id, a.quantite, a.manquants, a.created_at,
            m.id AS mission_id, m.code, m.statut, m.depart, m.retour, m.cloture_date, m.depot,
            v.nom AS voyageur
     FROM affectations a JOIN missions m ON m.id = a.mission_id JOIN voyageurs v ON v.id = m.voyageur_id
     WHERE a.ligne_id = $1 ORDER BY a.created_at`, [id])).rows;
  const affecte = traces.reduce((s, t) => s + Number(t.quantite), 0);
  res.json({ ...l, poids_unit: Number(l.poids_total) / Number(l.quantite), gain_piece: gainPiece(l),
    restant: Number(l.quantite) - affecte, traces });
});

/* ================= AFFECTATIONS (produit → valise) ================= */
inventaireRouter.post('/affectations', async (req, res) => {
  const p = z.object({
    mission_id: z.coerce.number().int(),
    ligne_id: z.coerce.number().int(),
    quantite: z.coerce.number().positive(),
  }).safeParse(req.body);
  if (!p.success) return res.status(400).json({ error: 'Affectation invalide.' });
  const d = p.data;
  const m = (await q(
    `SELECT m.statut, m.valise_close, m.code, v.nom AS voyageur
     FROM missions m JOIN voyageurs v ON v.id = m.voyageur_id WHERE m.id = $1`, [d.mission_id])).rows[0];
  if (!m) return res.status(404).json({ error: 'Mission introuvable.' });
  if (m.statut === 'cloturee' || m.valise_close) {
    return res.status(409).json({ error: 'Valise clôturée — rouvre-la d’abord.' });
  }
  const l = (await q(
    `SELECT l.quantite, l.produit, l.poids_total, c.nom AS chambre, COALESCE(SUM(a.quantite),0) AS affecte
     FROM bon_lignes l JOIN bons b ON b.id = l.bon_id JOIN chambres c ON c.id = b.chambre_id
     LEFT JOIN affectations a ON a.ligne_id = l.id
     WHERE l.id = $1 GROUP BY l.id, c.nom`, [d.ligne_id])).rows[0];
  if (!l) return res.status(404).json({ error: 'Produit introuvable.' });
  const restant = Number(l.quantite) - Number(l.affecte);
  if (d.quantite > restant + 1e-9) {
    return res.status(409).json({ error: `Il ne reste que ${restant} pièce(s) en stock.` });
  }
  // Une affectation existante pour la même ligne/mission → on cumule.
  const ex = (await q(
    'SELECT id FROM affectations WHERE ligne_id = $1 AND mission_id = $2', [d.ligne_id, d.mission_id])).rows[0];
  const row = ex
    ? (await q('UPDATE affectations SET quantite = quantite + $1 WHERE id = $2 RETURNING *',
        [d.quantite, ex.id])).rows[0]
    : (await q('INSERT INTO affectations (ligne_id, mission_id, quantite) VALUES ($1,$2,$3) RETURNING *',
        [d.ligne_id, d.mission_id, d.quantite])).rows[0];
  await audit(req.user.sub, 'valise_ajout', 'mission', d.mission_id, {
    code: m.code, voyageur: m.voyageur, produit: l.produit, quantite: d.quantite,
    kg: Math.round(d.quantite * Number(l.poids_total) / Number(l.quantite) * 10) / 10, chambre: l.chambre,
  });
  res.status(201).json(row);
});

inventaireRouter.delete('/affectations/:id', async (req, res) => {
  const id = Number(req.params.id);
  const a = (await q(
    `SELECT a.id, a.quantite, a.mission_id, m.statut, m.valise_close, m.code, l.produit
     FROM affectations a JOIN missions m ON m.id = a.mission_id JOIN bon_lignes l ON l.id = a.ligne_id
     WHERE a.id = $1`, [id])).rows[0];
  if (!a) return res.status(404).json({ error: 'Affectation introuvable.' });
  if (a.statut === 'cloturee' || a.valise_close) {
    return res.status(409).json({ error: 'Valise clôturée — rouvre-la d’abord.' });
  }
  await q('DELETE FROM affectations WHERE id = $1', [id]); // retour en stock
  await audit(req.user.sub, 'valise_retrait', 'mission', a.mission_id,
    { code: a.code, produit: a.produit, quantite: Number(a.quantite) });
  res.json({ ok: true });
});

/* ================= RAPPORT DÉPÔTS =================
   Ce que chaque dépôt (chambre) doit payer pour une mission clôturée. */
inventaireRouter.get('/depots/:missionId', async (req, res) => {
  const { rows } = await q(`
    SELECT c.id AS chambre_id, c.nom AS chambre, c.depot_adresse, c.depot_wilaya,
           l.produit, l.mode, l.prix, l.poids_total, l.quantite AS q_ligne, l.manque_rmb,
           a.quantite, a.manquants
    FROM affectations a
    JOIN bon_lignes l ON l.id = a.ligne_id
    JOIN bons b ON b.id = l.bon_id
    JOIN chambres c ON c.id = b.chambre_id
    WHERE a.mission_id = $1 ORDER BY c.nom, l.produit`, [Number(req.params.missionId)]);
  const parDepot = {};
  for (const r of rows) {
    const livre = Number(r.quantite) - Number(r.manquants);
    const gp = gainPiece(r);
    const d = parDepot[r.chambre_id] ??= {
      chambre: r.chambre, depot_adresse: r.depot_adresse, depot_wilaya: r.depot_wilaya,
      lignes: [], total_da: 0, kg: 0,
    };
    const pu = Number(r.poids_total) / Number(r.q_ligne);
    d.lignes.push({ produit: r.produit, quantite: livre, kg: livre * pu, da: livre * gp,
      manquants: Number(r.manquants), manque_rmb: Number(r.manque_rmb) });
    d.total_da += livre * gp;
    d.kg += livre * pu;
  }
  res.json(Object.values(parDepot));
});
