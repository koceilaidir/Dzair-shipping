import { Router } from 'express';
import { z } from 'zod';
import PDFDocument from 'pdfkit';
import { q } from './db.js';
import { requireAuth, requireRole } from './auth.js';
import { getReglages, coursOfficiels } from './reglages.js';

const FONT = new URL('../fonts/NotoSansSC-Regular.otf', import.meta.url).pathname;
const FONT_B = new URL('../fonts/NotoSansSC-Bold.otf', import.meta.url).pathname;

export const inventaireRouter = Router();
inventaireRouter.use(requireAuth, requireRole('admin'));

const audit = (userId, action, entite, id, details) => q(
  `INSERT INTO audit_log (user_id, action, entite, entite_id, details) VALUES ($1,$2,$3,$4,$5)`,
  [userId, action, entite, id, JSON.stringify(details)]);

const societeSchema = z.object({
  nom_cn: z.string().min(1).max(160),
  nom_en: z.string().max(160).optional().default(''),
  code_credit: z.string().max(40).optional().default(''),
  adresse_cn: z.string().max(300).optional().default(''),
  adresse_en: z.string().max(300).optional().default(''),
  tel: z.string().max(40).optional().default(''),
  email: z.string().max(120).optional().default(''),
  devise: z.enum(['USD', 'RMB', 'EUR']).optional().default('USD'),
  par_defaut: z.boolean().optional().default(false),
});

inventaireRouter.get('/societes', async (_req, res) => {
  res.json((await q('SELECT * FROM societes_facturation ORDER BY par_defaut DESC, id')).rows);
});

inventaireRouter.post('/societes', async (req, res) => {
  const p = societeSchema.safeParse(req.body);
  if (!p.success) return res.status(400).json({ error: 'Données invalides.' });
  const d = p.data;
  if (d.par_defaut) await q('UPDATE societes_facturation SET par_defaut = FALSE');
  const { rows } = await q(
    `INSERT INTO societes_facturation (nom_cn, nom_en, code_credit, adresse_cn, adresse_en, tel, email, devise, par_defaut)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
    [d.nom_cn, d.nom_en, d.code_credit, d.adresse_cn, d.adresse_en, d.tel, d.email, d.devise, d.par_defaut]);
  await audit(req.user.sub, 'create', 'societe', rows[0].id, { nom: d.nom_cn });
  res.status(201).json(rows[0]);
});

inventaireRouter.put('/societes/:id', async (req, res) => {
  const id = Number(req.params.id);
  const p = societeSchema.safeParse(req.body);
  if (!p.success) return res.status(400).json({ error: 'Données invalides.' });
  const d = p.data;
  if (d.par_defaut) await q('UPDATE societes_facturation SET par_defaut = FALSE');
  const { rows } = await q(
    `UPDATE societes_facturation SET nom_cn=$1, nom_en=$2, code_credit=$3, adresse_cn=$4, adresse_en=$5,
       tel=$6, email=$7, devise=$8, par_defaut=$9 WHERE id=$10 RETURNING *`,
    [d.nom_cn, d.nom_en, d.code_credit, d.adresse_cn, d.adresse_en, d.tel, d.email, d.devise, d.par_defaut, id]);
  if (!rows[0]) return res.status(404).json({ error: 'Société introuvable.' });
  await audit(req.user.sub, 'update', 'societe', id, { nom: d.nom_cn });
  res.json(rows[0]);
});

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
            COALESCE(SUM(CASE WHEN l.mode='kg' THEN l.poids_total*l.prix ELSE l.quantite*l.prix END),0) AS gain_da,
            COALESCE((SELECT SUM(r.quantite) FROM retours r JOIN bon_lignes bl ON bl.id = r.ligne_id
                      WHERE bl.bon_id = b.id),0) AS rendu
     FROM bons b LEFT JOIN bon_lignes l ON l.bon_id = b.id
     WHERE b.chambre_id = $1 GROUP BY b.id ORDER BY b.date DESC, b.id DESC`, [id])).rows;
  return c;
}

inventaireRouter.get('/chambres', async (_req, res) => {
  const { rows } = await q(`
    SELECT c.*,
           (SELECT COUNT(*) FROM bons b WHERE b.chambre_id = c.id)      AS nb_bons,
           (SELECT MAX(date) FROM bons b WHERE b.chambre_id = c.id)     AS dernier_bon,
           (SELECT b.id FROM bons b WHERE b.chambre_id = c.id ORDER BY b.date DESC, b.id DESC LIMIT 1) AS dernier_bon_id,
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
  bon_id: z.coerce.number().int().optional(),
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

  let b;
  if (d.bon_id) {
    b = (await q('SELECT * FROM bons WHERE id = $1 AND chambre_id = $2', [d.bon_id, d.chambre_id])).rows[0];
    if (!b) return res.status(404).json({ error: 'Bon introuvable pour cette chambre.' });
  } else {
    b = (await q(
      `INSERT INTO bons (chambre_id, date, note, user_id) VALUES ($1, COALESCE($2, CURRENT_DATE), $3, $4)
       RETURNING *`, [d.chambre_id, d.date ?? null, d.note, req.user.sub])).rows[0];
  }
  for (const l of d.lignes) {
    await q(
      `INSERT INTO bon_lignes (bon_id, produit, quantite, poids_total, manque_rmb, mode, prix)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [b.id, l.produit, l.quantite, l.poids_total, l.manque_rmb, l.mode, l.prix]);
  }
  const kg = d.lignes.reduce((t, l) => t + l.poids_total, 0);
  const da = d.lignes.reduce((t, l) => t + (l.mode === 'kg' ? l.prix * l.poids_total : l.prix * l.quantite), 0);
  await audit(req.user.sub, d.bon_id ? 'bon_ajout' : 'create', 'bon', b.id, {
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
    `SELECT l.*, COALESCE(SUM(a.quantite),0) AS affecte,
            COALESCE((SELECT SUM(r.quantite) FROM retours r WHERE r.ligne_id = l.id),0) AS rendu
     FROM bon_lignes l LEFT JOIN affectations a ON a.ligne_id = l.id
     WHERE l.bon_id = $1 GROUP BY l.id ORDER BY l.id`, [id])).rows;
  b.admin = b.user_id
    ? (await q('SELECT nom FROM users WHERE id = $1', [b.user_id])).rows[0]?.nom ?? null : null;
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

const gainPiece = (l) => l.mode === 'kg'
  ? Number(l.prix) * Number(l.poids_total) / Number(l.quantite)
  : Number(l.prix);

async function stockLignes() {

  const { rows } = await q(`
    SELECT l.*, b.date AS bon_date, b.chambre_id, c.nom AS chambre_nom,
           COALESCE((SELECT SUM(a.quantite) FROM affectations a WHERE a.ligne_id = l.id),0) AS affecte,
           COALESCE((SELECT SUM(a.quantite) FROM affectations a JOIN missions m ON m.id = a.mission_id
                     WHERE a.ligne_id = l.id AND m.statut <> 'cloturee'),0) AS en_cours,
           COALESCE((SELECT SUM(a.quantite) FROM affectations a JOIN missions m ON m.id = a.mission_id
                     WHERE a.ligne_id = l.id AND m.statut = 'cloturee'),0)  AS livre,
           COALESCE((SELECT SUM(r.quantite) FROM retours r WHERE r.ligne_id = l.id),0) AS rendu
    FROM bon_lignes l
    JOIN bons b ON b.id = l.bon_id
    JOIN chambres c ON c.id = b.chambre_id
    ORDER BY b.date DESC, l.id`);
  return rows.map((l) => {
    const restant = Number(l.quantite) - Number(l.affecte) - Number(l.rendu);
    const enCours = Number(l.en_cours);
    const poidsUnit = Number(l.poids_total) / Number(l.quantite);
    const gp = gainPiece(l);
    return {
      ...l,
      restant,
      en_cours: enCours,
      livre: Number(l.livre),
      rendu: Number(l.rendu),
      expose: restant + enCours,
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

async function missionsOuvertes({ excludeId = 0, dep = null, ret = null } = {}) {
  const params = [excludeId];

  let where = `m.id <> $1 AND m.statut = 'encours'
    AND (m.valise_close = FALSE OR (m.bagage_main AND m.bagage_main_close = FALSE))`;
  if (dep && ret) {
    params.push(dep, ret);
    where += ` AND m.depart IS NOT NULL AND m.retour IS NOT NULL AND m.depart <= $3 AND m.retour >= $2`;
  }
  const { rows } = await q(`
    SELECT m.id, m.code, m.objectif, m.kg_soute, m.cabine, m.billet, m.dem_cout, m.frais_visa,
           m.jours, m.budget_jour, m.douane, m.autres, m.manques_da, m.depart, m.retour,
           m.valise_sup, m.valise_sup_prix, m.valise_sup_kg, m.bagage_main, m.bagage_main_kg, m.saisie_da,
           v.nom AS voyageur,
           COALESCE((SELECT SUM(kg) FROM produits_mission p WHERE p.mission_id = m.id),0) AS kg_libre,
           COALESCE((SELECT SUM(kg*prix_kg) FROM produits_mission p WHERE p.mission_id = m.id),0) AS rev_libre
    FROM missions m JOIN voyageurs v ON v.id = m.voyageur_id
    WHERE ${where} ORDER BY m.retour NULLS LAST, m.id`, params);
  const out = [];
  for (const m of rows) {
    const aff = (await q(
      `SELECT a.quantite, l.mode, l.prix, l.poids_total, l.quantite AS q_ligne
       FROM affectations a JOIN bon_lignes l ON l.id = a.ligne_id WHERE a.mission_id = $1`, [m.id])).rows;
    let kg = Number(m.kg_libre), rev = Number(m.rev_libre);
    for (const a of aff) {
      const pu = Number(a.poids_total) / Number(a.q_ligne);
      kg += Number(a.quantite) * pu;
      rev += Number(a.quantite) * gainPiece(a);
    }

    const frais = Number(m.billet) + Number(m.dem_cout) + Number(m.frais_visa || 0) +
      Number(m.jours) * Number(m.budget_jour) + Number(m.douane) + Number(m.autres) +
      Number(m.manques_da || 0) + Number(m.saisie_da || 0) +
      (m.valise_sup ? Number(m.valise_sup_prix || 0) : 0);

    const cap = Number(m.kg_soute) + (m.valise_sup ? Number(m.valise_sup_kg || 23) : 0) +
      (m.bagage_main ? Number(m.bagage_main_kg || 8) : 0);
    const aCouvrir = Math.max(0, frais + Number(m.objectif) - rev);
    const kgLibre = Math.max(0, cap - kg);
    out.push({
      mission_id: m.id, code: m.code, voyageur: m.voyageur, depart: m.depart, retour: m.retour,
      manque_da: aCouvrir, kg_dispo: kgLibre,
      a_couvrir: aCouvrir, kg_libre: kgLibre,
      seuil_kg: kgLibre > 0 ? aCouvrir / kgLibre : 0,
    });
  }
  return out;
}

inventaireRouter.get('/stock', async (req, res) => {
  const lignes = await stockLignes();
  const reglages = await getReglages();

  let usdCny = 0;
  try { usdCny = (await coursOfficiels()).cny; } catch { usdCny = 0; }
  if (!usdCny && Number(reglages.taux_rmb) > 0) {
    usdCny = Number(reglages.taux_officiel) / Number(reglages.taux_rmb);
  }
  const out = { lignes, concurrents: [], ouvertes: [],
    taux_officiel: Number(reglages.taux_officiel), taux_rmb: Number(reglages.taux_rmb || 0),
    usd_cny: Math.round(usdCny * 100) / 100 };
  const mid = Number(req.query.mission);
  if (mid) {
    const me = (await q('SELECT depart, retour FROM missions WHERE id = $1', [mid])).rows[0];
    if (me) out.concurrents = await missionsOuvertes({ excludeId: mid, dep: me.depart, ret: me.retour });
  } else {

    out.ouvertes = await missionsOuvertes();
    const aCouvrir = out.ouvertes.reduce((s, m) => s + m.a_couvrir, 0);
    const kgLibre = out.ouvertes.reduce((s, m) => s + m.kg_libre, 0);
    out.seuil = { a_couvrir: aCouvrir, kg_libre: kgLibre, seuil_kg: kgLibre > 0 ? aCouvrir / kgLibre : 0,
      voyageurs: out.ouvertes.length };
  }
  res.json(out);
});

inventaireRouter.post('/retours', async (req, res) => {
  const p = z.object({
    ligne_id: z.coerce.number().int(),
    quantite: z.coerce.number().positive(),
    date: z.string().max(10).optional(),
  }).safeParse(req.body);
  if (!p.success) return res.status(400).json({ error: 'Retour invalide.' });
  const d = p.data;
  const l = (await q(
    `SELECT l.quantite, l.produit, c.nom AS chambre,
            COALESCE((SELECT SUM(a.quantite) FROM affectations a WHERE a.ligne_id = l.id),0) AS affecte,
            COALESCE((SELECT SUM(r.quantite) FROM retours r WHERE r.ligne_id = l.id),0) AS rendu
     FROM bon_lignes l JOIN bons b ON b.id = l.bon_id JOIN chambres c ON c.id = b.chambre_id
     WHERE l.id = $1`, [d.ligne_id])).rows[0];
  if (!l) return res.status(404).json({ error: 'Produit introuvable.' });
  const restant = Number(l.quantite) - Number(l.affecte) - Number(l.rendu);
  if (d.quantite > restant + 1e-9) {
    return res.status(409).json({ error: `Il ne reste que ${restant} pièce(s) à l'hôtel.` });
  }
  const { rows } = await q(
    `INSERT INTO retours (ligne_id, quantite, date, user_id)
     VALUES ($1,$2,COALESCE($3, CURRENT_DATE),$4) RETURNING *`,
    [d.ligne_id, d.quantite, d.date ?? null, req.user.sub]);
  await audit(req.user.sub, 'retour_chambre', 'bon', d.ligne_id,
    { chambre: l.chambre, produit: l.produit, quantite: d.quantite });
  res.status(201).json(rows[0]);
});

inventaireRouter.get('/bons/:id/pdf', async (req, res) => {
  const id = Number(req.params.id);
  const b = (await q(
    `SELECT b.*, c.nom AS chambre_nom, c.ville, c.depot_wilaya, c.depot_adresse,
            u.nom AS admin, u.tel AS admin_tel
     FROM bons b JOIN chambres c ON c.id = b.chambre_id
     LEFT JOIN users u ON u.id = b.user_id WHERE b.id = $1`, [id])).rows[0];
  if (!b) return res.status(404).json({ error: 'Bon introuvable.' });
  const contacts = (await q(
    'SELECT * FROM chambre_contacts WHERE chambre_id = $1 ORDER BY id', [b.chambre_id])).rows;
  const lignes = (await q(
    `SELECT l.*, COALESCE((SELECT SUM(r.quantite) FROM retours r WHERE r.ligne_id = l.id),0) AS rendu
     FROM bon_lignes l WHERE l.bon_id = $1 ORDER BY l.id`, [id])).rows;

  const fr = (d) => { const s = new Date(d).toISOString().slice(0, 10); return `${s.slice(8,10)}/${s.slice(5,7)}/${s.slice(0,4)}`; };
  const fm = (n) => Math.round(Number(n)).toLocaleString('fr-FR');
  const doc = new PDFDocument({ size: 'A4', margin: 46, info: { Title: `Bon ${b.chambre_nom}` } });
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="bon-${b.chambre_nom}-${id}.pdf"`);
  doc.pipe(res);
  const L = 46, R = doc.page.width - 46, CW = R - L;

  doc.font(FONT_B).fontSize(17).fillColor('#000')
    .text('BON DE RÉCUPÉRATION', L, 50, { width: CW, align: 'center' });
  if (b.note) {
    doc.font(FONT).fontSize(10).fillColor('#555')
      .text(b.note, L, doc.y + 3, { width: CW, align: 'center' });
  }
  doc.moveDown(0.9);

  const yMeta = doc.y;
  doc.font(FONT).fontSize(9.5).fillColor('#333')
    .text(b.admin ? `Récupéré par ${b.admin}${b.admin_tel ? ' · ' + b.admin_tel : ''}` : ' ',
      L, yMeta, { width: CW / 2, lineBreak: false });
  doc.text(fr(b.date), L + CW / 2, yMeta, { width: CW / 2, align: 'right', lineBreak: false });
  const yLine = yMeta + 15;
  doc.moveTo(L, yLine).lineTo(R, yLine).lineWidth(1).strokeColor('#000').stroke();

  const chine = contacts.filter((k) => (k.role || '').toLowerCase() === 'chine');
  const alg = contacts.filter((k) => (k.role || '').toLowerCase() !== 'chine');
  const yTop = yLine + 10;
  doc.fillColor('#000').font(FONT_B).fontSize(11).text(`Chambre ${b.chambre_nom}`, L, yTop, { width: CW / 2 - 10 });
  doc.font(FONT).fontSize(9.5).fillColor('#333')
    .text(`${b.ville || 'Canton'}`, L, doc.y, { width: CW / 2 - 10 })
    .text(chine.length ? `Contact Chine : ${chine.map((k) => `${k.nom}${k.tel ? ' ' + k.tel : ''}`).join(' · ')}` : ' ',
      L, doc.y, { width: CW / 2 - 10 });
  const yFinG = doc.y;
  doc.font(FONT_B).fontSize(11).fillColor('#000').text('Dépôt en Algérie', L + CW / 2, yTop, { width: CW / 2 });
  doc.font(FONT).fontSize(9.5).fillColor('#333')
    .text(`${b.depot_wilaya || '—'}${b.depot_adresse ? ' · ' + b.depot_adresse : ''}`, L + CW / 2, doc.y, { width: CW / 2 })
    .text(alg.length ? `Contact : ${alg.map((k) => `${k.nom}${k.tel ? ' ' + k.tel : ''}`).join(' · ')}` : ' ',
      L + CW / 2, doc.y, { width: CW / 2 });

  let y = Math.max(yFinG, doc.y) + 14;
  const cols = [CW - 305, 40, 55, 55, 75, 80];
  const xs = [L]; for (let i = 0; i < cols.length - 1; i++) xs.push(xs[i] + cols[i]);
  const rowH = 20;
  const cell = (i, t, yy, bold = false, align = 'left') =>
    doc.font(bold ? FONT_B : FONT).fontSize(9)
      .fillColor('#000').text(t, xs[i] + 4, yy + 5, { width: cols[i] - 8, align, lineBreak: false });
  const line = (yy) => doc.moveTo(L, yy).lineTo(R, yy).lineWidth(0.7).strokeColor('#999').stroke();
  line(y);
  const heads = ['Produit', 'Qté', 'Poids kg', 'Manque ¥', 'Prix', 'Total (DA)'];
  heads.forEach((h, i) => cell(i, h, y, true, i === 0 ? 'left' : 'right'));
  y += rowH; line(y);
  let totKg = 0, totQ = 0, totRendu = 0, totDA = 0;
  for (const l of lignes) {
    const rendu = Number(l.rendu);
    const totalLigne = l.mode === 'kg'
      ? Number(l.prix) * Number(l.poids_total)
      : Number(l.prix) * Number(l.quantite);
    cell(0, l.produit + (rendu > 0 ? `  (rendu ${rendu})` : ''), y);
    cell(1, String(Number(l.quantite)), y, false, 'right');
    cell(2, Number(l.poids_total).toFixed(1), y, false, 'right');
    cell(3, fm(l.manque_rmb), y, false, 'right');
    cell(4, `${fm(l.prix)}/${l.mode === 'kg' ? 'kg' : 'pc'}`, y, false, 'right');
    cell(5, fm(totalLigne), y, false, 'right');
    totKg += Number(l.poids_total); totQ += Number(l.quantite); totRendu += rendu;
    totDA += totalLigne;
    y += rowH; line(y);
  }
  cell(0, `TOTAL${totRendu > 0 ? `  ·  dont ${totRendu} pc rendues — net ${totQ - totRendu} pc` : ''}`, y, true);
  cell(1, String(totQ), y, true, 'right');
  cell(2, totKg.toFixed(1), y, true, 'right');
  cell(5, fm(totDA), y, true, 'right');
  y += rowH; line(y);
  doc.end();
});

inventaireRouter.get('/lignes/:id', async (req, res) => {
  const id = Number(req.params.id);
  const l = (await q(
    `SELECT l.*, b.date AS bon_date, b.note AS bon_note, c.id AS chambre_id, c.nom AS chambre_nom,
            c.depot_wilaya, c.depot_adresse
     FROM bon_lignes l JOIN bons b ON b.id = l.bon_id JOIN chambres c ON c.id = b.chambre_id
     WHERE l.id = $1`, [id])).rows[0];
  if (!l) return res.status(404).json({ error: 'Produit introuvable.' });
  const traces = (await q(
    `SELECT a.id, a.quantite, a.manquants, a.saisis, a.emplacement, a.created_at,
            m.id AS mission_id, m.code, m.statut, m.depart, m.retour, m.cloture_date, m.depot,
            v.nom AS voyageur
     FROM affectations a JOIN missions m ON m.id = a.mission_id JOIN voyageurs v ON v.id = m.voyageur_id
     WHERE a.ligne_id = $1 ORDER BY a.created_at`, [id])).rows;
  const affecte = traces.reduce((s, t) => s + Number(t.quantite), 0);
  const retours = (await q(
    `SELECT r.quantite, r.date, u.nom AS admin FROM retours r
     LEFT JOIN users u ON u.id = r.user_id WHERE r.ligne_id = $1 ORDER BY r.date, r.id`, [id])).rows;
  const rendu = retours.reduce((s, r) => s + Number(r.quantite), 0);
  res.json({ ...l, poids_unit: Number(l.poids_total) / Number(l.quantite), gain_piece: gainPiece(l),
    restant: Number(l.quantite) - affecte - rendu, rendu, retours, traces });
});

inventaireRouter.post('/affectations', async (req, res) => {
  const p = z.object({
    mission_id: z.coerce.number().int(),
    ligne_id: z.coerce.number().int(),
    quantite: z.coerce.number().positive(),

    emplacement: z.enum(['soute', 'main']).optional().default('soute'),
    prix_declare: z.coerce.number().positive().optional(),
  }).safeParse(req.body);
  if (!p.success) return res.status(400).json({ error: 'Affectation invalide.' });
  const d = p.data;
  if (d.emplacement === 'soute' && !(Number(d.prix_declare) > 0)) {
    return res.status(400).json({ error: 'Prix déclaré requis pour un produit en soute.' });
  }
  if (d.emplacement === 'main') d.prix_declare = undefined;
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

  const ex = (await q(
    `SELECT a.id FROM affectations a WHERE a.ligne_id = $1 AND a.mission_id = $2
       AND a.emplacement = $3
       AND NOT EXISTS (SELECT 1 FROM factures f WHERE f.mission_id = a.mission_id AND f.statut = 'emise'
                       AND f.lignes @> jsonb_build_array(jsonb_build_object('affectation_id', a.id)))
     ORDER BY a.id DESC LIMIT 1`, [d.ligne_id, d.mission_id, d.emplacement])).rows[0];
  const row = ex
    ? (await q('UPDATE affectations SET quantite = quantite + $1, prix_declare = $3 WHERE id = $2 RETURNING *',
        [d.quantite, ex.id, d.prix_declare ?? null])).rows[0]
    : (await q(
        `INSERT INTO affectations (ligne_id, mission_id, quantite, prix_declare, emplacement)
         VALUES ($1,$2,$3,$4,$5) RETURNING *`,
        [d.ligne_id, d.mission_id, d.quantite, d.prix_declare ?? null, d.emplacement])).rows[0];

  if (d.emplacement === 'soute') {
    await q('UPDATE bon_lignes SET prix_declare = $1 WHERE id = $2', [d.prix_declare, d.ligne_id]);
  }
  await audit(req.user.sub, 'valise_ajout', 'mission', d.mission_id, {
    code: m.code, voyageur: m.voyageur, produit: l.produit, quantite: d.quantite,
    kg: Math.round(d.quantite * Number(l.poids_total) / Number(l.quantite) * 10) / 10, chambre: l.chambre,
    prix_declare: d.prix_declare ?? null,
    ...(d.emplacement === 'main' ? { bagage_main: true } : {}),
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

  const fac = (await q(
    `SELECT numero FROM factures WHERE mission_id = $1 AND statut = 'emise'
       AND lignes @> $2::jsonb LIMIT 1`, [a.mission_id, JSON.stringify([{ affectation_id: id }])])).rows[0];
  if (fac) return res.status(409).json({ error: `Produit déjà sur la facture n° ${fac.numero} — annule la facture d’abord.` });
  await q('DELETE FROM affectations WHERE id = $1', [id]);
  await audit(req.user.sub, 'valise_retrait', 'mission', a.mission_id,
    { code: a.code, produit: a.produit, quantite: Number(a.quantite) });
  res.json({ ok: true });
});

async function rapportDepots(missionId) {
  const { rows } = await q(`
    SELECT c.id AS chambre_id, c.nom AS chambre, c.depot_adresse, c.depot_wilaya,
           l.produit, l.mode, l.prix, l.poids_total, l.quantite AS q_ligne, l.manque_rmb,
           a.quantite, a.manquants, a.saisis, a.emplacement
    FROM affectations a
    JOIN bon_lignes l ON l.id = a.ligne_id
    JOIN bons b ON b.id = l.bon_id
    JOIN chambres c ON c.id = b.chambre_id
    WHERE a.mission_id = $1 ORDER BY c.nom, l.produit`, [missionId]);
  const statuts = new Map((await q(
    `SELECT chambre_id, statut FROM mission_depots WHERE mission_id = $1`, [missionId]))
    .rows.map((s) => [s.chambre_id, s.statut]));
  const enc = new Map((await q(
    `SELECT chambre_id, SUM(montant) AS t FROM paiements
     WHERE mission_id = $1 AND chambre_id IS NOT NULL GROUP BY chambre_id`, [missionId]))
    .rows.map((p) => [p.chambre_id, Number(p.t)]));
  const parDepot = {};
  for (const r of rows) {

    const livre = Number(r.quantite) - Number(r.manquants) - Number(r.saisis || 0);
    const gp = gainPiece(r);
    const d = parDepot[r.chambre_id] ??= {
      chambre_id: r.chambre_id,
      chambre: r.chambre, depot_adresse: r.depot_adresse, depot_wilaya: r.depot_wilaya,
      statut: statuts.get(r.chambre_id) || 'a_verifier',
      encaisse: enc.get(r.chambre_id) || 0,
      lignes: [], total_da: 0, kg: 0,
    };
    const pu = Number(r.poids_total) / Number(r.q_ligne);
    d.lignes.push({ produit: r.produit, quantite: livre, kg: livre * pu, da: livre * gp,
      manquants: Number(r.manquants), saisis: Number(r.saisis || 0), manque_rmb: Number(r.manque_rmb),
      emplacement: r.emplacement || 'soute', mode: r.mode, prix: Number(r.prix) });
    d.total_da += livre * gp;
    d.kg += livre * pu;
  }
  return Object.values(parDepot);
}

inventaireRouter.get('/depots/:missionId', async (req, res) => {
  res.json(await rapportDepots(Number(req.params.missionId)));
});

inventaireRouter.post('/depots/:missionId/statut', async (req, res) => {
  const p = z.object({
    chambre_id: z.coerce.number().int(),
    statut: z.enum(['a_verifier', 'verifie', 'depose', 'paye']),
  }).safeParse(req.body);
  if (!p.success) return res.status(400).json({ error: 'Statut invalide.' });
  const missionId = Number(req.params.missionId);
  const d = p.data;
  await q(
    `INSERT INTO mission_depots (mission_id, chambre_id, statut, user_id, updated_at)
     VALUES ($1,$2,$3,$4,now())
     ON CONFLICT (mission_id, chambre_id)
     DO UPDATE SET statut = $3, user_id = $4, updated_at = now()`,
    [missionId, d.chambre_id, d.statut, req.user.sub]);
  const ch = (await q('SELECT nom FROM chambres WHERE id = $1', [d.chambre_id])).rows[0];
  const mc = (await q('SELECT code FROM missions WHERE id = $1', [missionId])).rows[0];
  await audit(req.user.sub, 'depot_statut', 'mission', missionId,
    { code: mc?.code, depot: ch?.nom, statut: d.statut });
  res.json({ ok: true });
});

inventaireRouter.get('/depots/:missionId/pdf/:chambreId', async (req, res) => {
  const missionId = Number(req.params.missionId), chambreId = Number(req.params.chambreId);
  const m = (await q('SELECT code FROM missions WHERE id = $1', [missionId])).rows[0];
  if (!m) return res.status(404).json({ error: 'Mission introuvable.' });
  const dep = (await rapportDepots(missionId)).find((d) => d.chambre_id === chambreId);
  if (!dep) return res.status(404).json({ error: 'Dépôt introuvable pour cette mission.' });
  const ch = (await q('SELECT nom, ville FROM chambres WHERE id = $1', [chambreId])).rows[0];
  const contacts = (await q(
    `SELECT * FROM chambre_contacts WHERE chambre_id = $1 ORDER BY id`, [chambreId])).rows;
  const chine = contacts.filter((k) => (k.role || '').toLowerCase() === 'chine');
  const alg = contacts.filter((k) => (k.role || '').toLowerCase() !== 'chine');

  const bons = (await q(
    `SELECT DISTINCT b.id, b.date, b.note, u.nom AS admin, u.tel AS admin_tel
     FROM affectations a
     JOIN bon_lignes l ON l.id = a.ligne_id
     JOIN bons b ON b.id = l.bon_id
     LEFT JOIN users u ON u.id = b.user_id
     WHERE a.mission_id = $1 AND b.chambre_id = $2
     ORDER BY b.date DESC, b.id DESC`, [missionId, chambreId])).rows;
  const dernier = bons[0];
  const notes = [...new Set(bons.map((x) => (x.note || '').trim()).filter(Boolean))].join(' · ');

  const fr = (d) => { const s = new Date(d ?? Date.now()).toISOString().slice(0, 10); return `${s.slice(8,10)}/${s.slice(5,7)}/${s.slice(0,4)}`; };
  const fm = (n) => Math.round(Number(n)).toLocaleString('fr-FR');
  const doc = new PDFDocument({ size: 'A4', margin: 46, info: { Title: `Remise ${dep.chambre}` } });
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="remise-${dep.chambre}-${m.code}.pdf"`);
  doc.pipe(res);
  const L = 46, R = doc.page.width - 46, CW = R - L;

  doc.font(FONT_B).fontSize(17).fillColor('#000')
    .text('BON DE REMISE', L, 50, { width: CW, align: 'center' });
  if (notes) {
    doc.font(FONT).fontSize(10).fillColor('#555')
      .text(notes, L, doc.y + 3, { width: CW, align: 'center' });
  }
  doc.moveDown(0.9);

  const yMeta = doc.y;
  doc.font(FONT).fontSize(9.5).fillColor('#333')
    .text(dernier?.admin ? `Récupéré par ${dernier.admin}${dernier.admin_tel ? ' · ' + dernier.admin_tel : ''}` : ' ',
      L, yMeta, { width: CW / 2, lineBreak: false });
  doc.text(dernier ? fr(dernier.date) : ' ', L + CW / 2, yMeta,
    { width: CW / 2, align: 'right', lineBreak: false });
  const yLine = yMeta + 15;
  doc.moveTo(L, yLine).lineTo(R, yLine).lineWidth(1).strokeColor('#000').stroke();

  const yTop = yLine + 10;
  doc.fillColor('#000').font(FONT_B).fontSize(11)
    .text(`Chambre ${ch?.nom ?? dep.chambre}`, L, yTop, { width: CW / 2 - 10 });
  doc.font(FONT).fontSize(9.5).fillColor('#333')
    .text(`${ch?.ville || 'Canton'}`, L, doc.y, { width: CW / 2 - 10 })
    .text(chine.length ? `Contact Chine : ${chine.map((k) => `${k.nom}${k.tel ? ' ' + k.tel : ''}`).join(' · ')}` : ' ',
      L, doc.y, { width: CW / 2 - 10 });
  const yFinG = doc.y;
  doc.font(FONT_B).fontSize(11).fillColor('#000').text('Dépôt en Algérie', L + CW / 2, yTop, { width: CW / 2 });
  doc.font(FONT).fontSize(9.5).fillColor('#333')
    .text(`${dep.depot_wilaya || '—'}${dep.depot_adresse ? ' · ' + dep.depot_adresse : ''}`,
      L + CW / 2, doc.y, { width: CW / 2 })
    .text(alg.length ? `Contact : ${alg.map((k) => `${k.nom}${k.tel ? ' ' + k.tel : ''}`).join(' · ')}` : ' ',
      L + CW / 2, doc.y, { width: CW / 2 });

  let y = Math.max(yFinG, doc.y) + 14;
  const cols = [CW - 255, 45, 60, 70, 80];
  const xs = [L]; for (let i = 0; i < cols.length - 1; i++) xs.push(xs[i] + cols[i]);
  const rowH = 20;
  const cell = (i, t, yy, bold = false, align = 'left') =>
    doc.font(bold ? FONT_B : FONT).fontSize(9)
      .fillColor('#000').text(t, xs[i] + 4, yy + 5, { width: cols[i] - 8, align, lineBreak: false });
  const line = (yy) => doc.moveTo(L, yy).lineTo(R, yy).lineWidth(0.7).strokeColor('#999').stroke();
  line(y);
  ['Produit', 'Qté', 'Poids kg', 'Prix', 'Total (DA)']
    .forEach((h, i) => cell(i, h, y, true, i === 0 ? 'left' : 'right'));
  y += rowH; line(y);
  for (const l of dep.lignes) {
    const extra = [];
    if (l.manquants > 0) extra.push(`${l.manquants} manquante(s)`);
    if (l.saisis > 0) extra.push(`${l.saisis} saisie(s) douane`);
    cell(0, l.produit + (extra.length ? `  (${extra.join(' · ')} — remboursées)` : ''), y);
    cell(1, String(Number(l.quantite)), y, false, 'right');
    cell(2, Number(l.kg).toFixed(1), y, false, 'right');
    cell(3, `${fm(l.prix)}/${l.mode === 'kg' ? 'kg' : 'pc'}`, y, false, 'right');
    cell(4, fm(l.da), y, false, 'right');
    y += rowH; line(y);
  }
  cell(0, 'TOTAL DÛ PAR LE DÉPÔT', y, true);
  cell(2, Number(dep.kg).toFixed(1), y, true, 'right');
  cell(4, fm(dep.total_da), y, true, 'right');
  y += rowH; line(y);
  if (dep.encaisse > 0) {
    doc.font(FONT).fontSize(9.5).fillColor('#333')
      .text(`Déjà versé : ${fm(dep.encaisse)} DA — reste : ${fm(dep.total_da - dep.encaisse)} DA`, L, y + 10);
  }
  doc.end();
});
