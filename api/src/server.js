import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import 'dotenv/config';
import fs from 'node:fs';
import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { q } from './db.js';
import { authRouter, requireAuth, requireRole } from './auth.js';
import { missionsRouter } from './missions.js';
import { reglagesRouter } from './reglages.js';
import { rapportsRouter } from './rapports.js';
import { inventaireRouter } from './inventaire.js';
import { facturesRouter } from './factures.js';
import { messagesRouter } from './messages.js';
import { sejoursRouter } from './sejours.js';

process.on('unhandledRejection', (err) => console.error('⚠ Rejet non géré :', err));
process.on('uncaughtException', (err) => console.error('⚠ Exception non gérée :', err));

try {
  const schema = fs.readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8');
  await q(schema);
  console.log('✓ Schéma de base vérifié/appliqué');
} catch (err) {
  console.error('⚠ Application du schéma échouée :', err.message);
}

const app = express();

app.set('trust proxy', 1);
app.use(helmet());
app.use(cors({ origin: process.env.CORS_ORIGIN?.split(',') ?? true }));
app.use(express.json({ limit: '10mb' }));
app.use(rateLimit({ windowMs: 60 * 1000, max: 300 }));

app.get('/api/health', (_req, res) => res.json({ ok: true, service: 'dzair-shipping-api' }));

app.use('/api/auth', authRouter);
app.use('/api/missions', missionsRouter);
app.use('/api/reglages', reglagesRouter);
app.use('/api/rapports', rapportsRouter);
app.use('/api/inventaire', inventaireRouter);
app.use('/api/factures', facturesRouter);
app.use('/api/messages', messagesRouter);
app.use('/api/sejours', sejoursRouter);

const voyageurSchema = z.object({
  nom: z.string().min(2).max(120),
  tel: z.string().max(30).optional(),
  comm_mode: z.enum(['kg', 'pct', 'fixe']).default('pct'),
  comm_val: z.number().nonnegative().default(0),
  statut_dispo: z.enum(['disponible', 'indisponible', 'limite']).default('disponible'),
  bagages: z.number().int().min(1).max(4).default(2),
  depuis: z.string().max(20).optional(),
  dette_active: z.boolean().default(false),
  dette_montant: z.number().nonnegative().default(0),
  passeport_expire: z.string().max(10).nullable().optional(),
  autorisation_expire: z.string().max(10).nullable().optional(),
  devise_compte: z.enum(['USD', 'EUR']).default('USD'),
  allocation_eligible: z.boolean().default(true),
  solde_devises: z.coerce.number().nonnegative().optional(),

  nom_passeport: z.string().max(160).nullable().optional(),
  adresse: z.string().max(300).nullable().optional(),
  wilaya: z.string().max(80).nullable().optional(),

  email: z.string().email().max(200).nullable().optional(),
  username: z.string().trim().min(3).max(40)
    .regex(/^[a-zA-Z0-9._-]+$/).nullable().optional(),
});

function motDePasseInitial() {
  const alphabet = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
  let s = '';
  for (const b of crypto.randomBytes(10)) s += alphabet[b % alphabet.length];
  return s;
}

function refus(message) {
  const err = new Error(message);
  err.status = 409;
  throw err;
}

async function creerCompteVoyageur(email, username, nom) {
  const mail = email ? email.trim().toLowerCase() : null;
  const pseudo = username ? username.trim() : null;
  if (!mail && !pseudo) {
    const err = new Error('Il faut au moins un nom d’utilisateur ou un email.');
    err.status = 400;
    throw err;
  }
  if (mail && (await q('SELECT id FROM users WHERE lower(email) = $1', [mail])).rows[0]) {
    refus('Cet email a déjà un compte. Choisis-en un autre.');
  }
  if (pseudo
      && (await q('SELECT id FROM users WHERE lower(username) = $1',
        [pseudo.toLowerCase()])).rows[0]) {
    refus('Ce nom d’utilisateur est déjà pris. Choisis-en un autre.');
  }
  const mdp = motDePasseInitial();
  const hash = await bcrypt.hash(mdp, 10);
  const u = (await q(
    `INSERT INTO users (email, username, password_hash, role, nom)
     VALUES ($1,$2,$3,'voyageur',$4) RETURNING id`,
    [mail, pseudo, hash, nom],
  )).rows[0];
  return { user_id: u.id, mot_de_passe_initial: mdp, identifiant: pseudo || mail };
}

app.get('/api/voyageurs', requireAuth, requireRole('admin'), async (_req, res) => {

  const { rows } = await q(`
    SELECT v.*, (SELECT email FROM users u WHERE u.id = v.user_id) AS email,
           (SELECT username FROM users u WHERE u.id = v.user_id) AS username,
           COALESCE(mm.n, 0) AS missions_mois,
           CASE WHEN v.statut_dispo = 'indisponible' THEN 'indisponible'
                WHEN COALESCE(mm.n, 0) >= 2          THEN 'limite'
                ELSE 'disponible' END AS statut_effectif
    FROM voyageurs v
    LEFT JOIN (
      SELECT voyageur_id, COUNT(*) AS n FROM missions
      WHERE statut <> 'annulee'
        AND to_char(depart, 'YYYY-MM') = to_char(CURRENT_DATE, 'YYYY-MM')
      GROUP BY voyageur_id
    ) mm ON mm.voyageur_id = v.id
    WHERE NOT v.est_admin
    ORDER BY v.nom`);
  res.json(rows.map((r) => ({ ...r, statut_dispo: r.statut_effectif })));
});

app.get('/api/admins', requireAuth, requireRole('admin'), async (_req, res) => {
  const { rows } = await q(`
    SELECT u.id, u.nom, u.email, u.username,
           (u.photo IS NOT NULL) AS a_photo,
           v.id AS voyageur_id
    FROM users u
    LEFT JOIN voyageurs v ON v.user_id = u.id AND v.est_admin
    WHERE u.role = 'admin' AND u.actif
    ORDER BY u.nom`);
  res.json(rows);
});

app.post('/api/voyageurs', requireAuth, requireRole('admin'), async (req, res) => {
  const parsed = voyageurSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.issues });
  const v = parsed.data;

  let compte = null;
  if (v.email || v.username) {
    try { compte = await creerCompteVoyageur(v.email, v.username, v.nom); }
    catch (e) { return res.status(e.status || 500).json({ error: e.message }); }
  }

  const { rows } = await q(
    `INSERT INTO voyageurs (nom, tel, comm_mode, comm_val, bagages, depuis, dette_active,
       dette_montant, passeport_expire, autorisation_expire, devise_compte, allocation_eligible,
       statut_dispo, nom_passeport, adresse, wilaya, user_id)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17) RETURNING *`,
    [v.nom, v.tel ?? null, v.comm_mode, v.comm_val, v.bagages, v.depuis ?? null,
     v.dette_active, v.dette_montant, v.passeport_expire ?? null, v.autorisation_expire ?? null,
     v.devise_compte, v.allocation_eligible, v.statut_dispo,
     v.nom_passeport ?? null, v.adresse ?? null, v.wilaya ?? null, compte?.user_id ?? null],
  );
  await q(
    `INSERT INTO audit_log (user_id, action, entite, entite_id, details)
     VALUES ($1,'create','voyageur',$2,$3)`,
    [req.user.sub, rows[0].id, JSON.stringify({ nom: v.nom, compte: !!compte })],
  );

  res.status(201).json({ ...rows[0], email: v.email ?? null, username: v.username ?? null,
    identifiant: compte?.identifiant ?? null,
    mot_de_passe_initial: compte?.mot_de_passe_initial ?? null });
});

app.put('/api/voyageurs/:id', requireAuth, requireRole('admin'), async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return res.status(400).json({ error: 'Identifiant invalide.' });
  const parsed = voyageurSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.issues });

  const cur = (await q('SELECT * FROM voyageurs WHERE id = $1', [id])).rows[0];
  if (!cur) return res.status(404).json({ error: 'Voyageur introuvable.' });
  const v = { ...cur, ...parsed.data };

  let compte = null;
  if ((parsed.data.email || parsed.data.username) && !cur.user_id) {
    try {
      compte = await creerCompteVoyageur(parsed.data.email, parsed.data.username, v.nom);
    } catch (e) { return res.status(e.status || 500).json({ error: e.message }); }
    await q('UPDATE voyageurs SET user_id = $1 WHERE id = $2', [compte.user_id, id]);
  } else if (cur.user_id && (parsed.data.email !== undefined
      || parsed.data.username !== undefined)) {
    if (parsed.data.email) {
      const mail = parsed.data.email.trim().toLowerCase();
      const pris = (await q('SELECT id FROM users WHERE lower(email) = $1 AND id <> $2',
        [mail, cur.user_id])).rows[0];
      if (pris) return res.status(409).json({ error: 'Cet email est déjà pris.' });
      await q('UPDATE users SET email = $1 WHERE id = $2', [mail, cur.user_id]);
    }
    if (parsed.data.username) {
      const pseudo = parsed.data.username.trim();
      const pris = (await q('SELECT id FROM users WHERE lower(username) = $1 AND id <> $2',
        [pseudo.toLowerCase(), cur.user_id])).rows[0];
      if (pris) return res.status(409).json({ error: 'Ce nom d’utilisateur est déjà pris.' });
      await q('UPDATE users SET username = $1 WHERE id = $2', [pseudo, cur.user_id]);
    }
  }

  if (String(v.comm_mode) !== String(cur.comm_mode) || Number(v.comm_val) !== Number(cur.comm_val)) {
    await q(
      `INSERT INTO historique_commissions
         (voyageur_id, ancien_mode, ancienne_val, nouveau_mode, nouvelle_val, user_id)
       VALUES ($1,$2,$3,$4,$5,$6)`,
      [id, cur.comm_mode, cur.comm_val, v.comm_mode, v.comm_val, req.user.sub],
    );
  }
  const { rows } = await q(
    `UPDATE voyageurs SET nom=$1, tel=$2, comm_mode=$3, comm_val=$4, bagages=$5,
       depuis=$6, dette_active=$7, dette_montant=$8, passeport_expire=$9, autorisation_expire=$10,
       devise_compte=$11, allocation_eligible=$12, statut_dispo=$13,
       nom_passeport=$14, adresse=$15, wilaya=$16, solde_devises=$17
     WHERE id=$18 RETURNING *`,
    [v.nom, v.tel ?? null, v.comm_mode, v.comm_val, v.bagages, v.depuis ?? null,
     v.dette_active, v.dette_montant, v.passeport_expire ?? null, v.autorisation_expire ?? null,
     v.devise_compte, v.allocation_eligible, v.statut_dispo,
     v.nom_passeport ?? null, v.adresse ?? null, v.wilaya ?? null,
     v.solde_devises ?? cur.solde_devises, id],
  );
  const { email: _e, username: _u, ...auditables } = parsed.data;
  await q(
    `INSERT INTO audit_log (user_id, action, entite, entite_id, details)
     VALUES ($1,'update','voyageur',$2,$3)`,
    [req.user.sub, id, JSON.stringify({ ...auditables, ...(compte ? { compte: true } : {}) })],
  );
  res.json({ ...rows[0], identifiant: compte?.identifiant ?? null,
    mot_de_passe_initial: compte?.mot_de_passe_initial ?? null });
});

app.delete('/api/voyageurs/:id', requireAuth, requireRole('admin'), async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return res.status(400).json({ error: 'Identifiant invalide.' });
  const n = (await q('SELECT COUNT(*) AS n FROM missions WHERE voyageur_id = $1', [id])).rows[0].n;
  if (Number(n) > 0) {
    return res.status(409).json({
      error: 'Ce voyageur a des missions enregistrées — on ne l’efface pas, son historique compte. Supprime d’abord ses missions si c’était un test.',
    });
  }
  await q('DELETE FROM tranches_devises WHERE voyageur_id = $1', [id]);
  await q('DELETE FROM remboursements_dette WHERE voyageur_id = $1', [id]);
  await q('DELETE FROM historique_commissions WHERE voyageur_id = $1', [id]);

  await q(`UPDATE users SET actif = FALSE
           WHERE id = (SELECT user_id FROM voyageurs WHERE id = $1) AND role = 'voyageur'`, [id]);
  const r = await q('DELETE FROM voyageurs WHERE id = $1 RETURNING nom', [id]);
  if (!r.rows[0]) return res.status(404).json({ error: 'Voyageur introuvable.' });
  await q(`INSERT INTO audit_log (user_id, action, entite, entite_id, details)
           VALUES ($1,'delete','voyageur',$2,$3)`,
    [req.user.sub, id, JSON.stringify({ nom: r.rows[0].nom })]);
  res.json({ ok: true });
});

const TABLES_COMPTA = ['mission_docs', 'mission_depots', 'demandes_suppression', 'retours',
  'factures', 'affectations', 'produits_mission', 'paiements', 'tranches_devises',
  'depenses_sejour', 'sejours', 'missions', 'remboursements_dette', 'historique_commissions'];
const TABLES_CHAMBRES = ['bon_lignes', 'bons', 'chambre_contacts', 'chambres'];

app.post('/api/admin/reinitialiser', requireAuth, requireRole('admin'), async (req, res) => {
  const parsed = z.object({
    confirmation: z.string(),
    chambres: z.boolean().optional().default(false),
    messages: z.boolean().optional().default(false),
    activite: z.boolean().optional().default(false),
  }).safeParse(req.body);
  if (!parsed.success || parsed.data.confirmation !== 'REINITIALISER') {
    return res.status(400).json({
      error: 'Tape REINITIALISER en majuscules pour confirmer.' });
  }
  const d = parsed.data;
  const tables = [...TABLES_COMPTA];
  if (d.chambres) tables.push(...TABLES_CHAMBRES);
  if (d.messages) tables.push('messages');
  if (d.activite) tables.push('audit_log');

  await q(`TRUNCATE TABLE ${tables.join(', ')} RESTART IDENTITY CASCADE`);
  await q(`UPDATE voyageurs SET solde_devises = 0, dette_active = FALSE,
             dette_montant = 0, dette_rembourse = 0, allocation_derniere = NULL,
             statut_dispo = 'disponible'`);
  await q(`INSERT INTO audit_log (user_id, action, entite, entite_id, details)
           VALUES ($1,'reinitialisation','base',NULL,$2)`,
    [req.user.sub, JSON.stringify({
      tables: tables.length, chambres: d.chambres,
      messages: d.messages, activite: d.activite })]);

  const restants = (await q(
    `SELECT COUNT(*) FILTER (WHERE role = 'admin') AS admins,
            COUNT(*) FILTER (WHERE role = 'voyageur') AS voyageurs
     FROM users WHERE actif`)).rows[0];
  res.json({
    ok: true,
    comptes_gardes: {
      admins: Number(restants.admins), voyageurs: Number(restants.voyageurs) },
  });
});

app.use((err, req, res, _next) => {
  console.error(`⚠ ${req.method} ${req.originalUrl} →`, err);
  const technique = [err?.code, err?.constraint, err?.detail || err?.message]
    .filter(Boolean).join(' · ');
  res.status(500).json({
    error: req.user?.role === 'admin' && technique
      ? `Erreur serveur — ${technique}`
      : 'Erreur serveur.',
  });
});

const port = Number(process.env.PORT || 3000);
app.listen(port, () => console.log(`✈ API Dzair Shipping sur http://localhost:${port}`));
