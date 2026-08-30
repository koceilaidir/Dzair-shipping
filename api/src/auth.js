import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { q } from './db.js';

const SECRET = process.env.JWT_SECRET;
if (!SECRET || SECRET.length < 32) {
  console.error('⚠ JWT_SECRET manquant ou trop court dans .env (64+ caractères recommandés).');
  process.exit(1);
}

export const authRouter = Router();

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Trop de tentatives. Réessaie dans 15 minutes.' },
});

const loginSchema = z.object({
  email: z.string().email().max(200),
  password: z.string().min(1).max(200),
  souvenir: z.boolean().optional().default(false),
});

authRouter.post('/login', loginLimiter, async (req, res) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Requête invalide.' });

  const { email, password, souvenir } = parsed.data;
  const { rows } = await q(
    'SELECT id, email, password_hash, role, nom, actif FROM users WHERE email = $1',
    [email.toLowerCase()],
  );
  const user = rows[0];

  if (!user || !user.actif || !(await bcrypt.compare(password, user.password_hash))) {
    return res.status(401).json({ error: 'Identifiants incorrects.' });
  }

  const token = jwt.sign(
    { sub: user.id, role: user.role, nom: user.nom },
    SECRET,
    { expiresIn: souvenir ? '30d' : (process.env.JWT_EXPIRES || '12h') },
  );
  res.json({ token, role: user.role, nom: user.nom });
});

export function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Non authentifié.' });
  try {
    req.user = jwt.verify(token, SECRET);
    next();
  } catch {
    return res.status(401).json({ error: 'Session expirée, reconnecte-toi.' });
  }
}

export const requireRole = (...roles) => (req, res, next) => {
  if (!req.user || !roles.includes(req.user.role)) {
    return res.status(403).json({ error: 'Accès refusé.' });
  }
  next();
};

authRouter.get('/moi', requireAuth, async (req, res) => {
  const u = (await q(`
    SELECT u.id, u.email, u.nom, u.role, u.tel,
           (u.photo IS NOT NULL) AS a_photo,
           v.id IS NOT NULL AS est_voyageur, v.adresse, v.wilaya
    FROM users u LEFT JOIN voyageurs v ON v.user_id = u.id
    WHERE u.id = $1`, [req.user.sub])).rows[0];
  if (!u) return res.status(404).json({ error: 'Compte introuvable.' });
  res.json(u);
});

authRouter.put('/moi', requireAuth, async (req, res) => {
  const parsed = z.object({
    nom: z.string().trim().min(2).max(120).optional(),
    tel: z.string().max(40).optional(),
    email: z.string().email().max(200).optional(),
    adresse: z.string().max(300).optional(),
    wilaya: z.string().max(80).optional(),
    password: z.string().min(8).max(200).optional(),
  }).safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({
      error: 'Données invalides (mot de passe : 8 caractères minimum, email valide).' });
  }
  const d = parsed.data;
  if (d.email !== undefined) {
    const mail = d.email.trim().toLowerCase();
    const deja = (await q('SELECT id FROM users WHERE email = $1 AND id <> $2',
      [mail, req.user.sub])).rows[0];
    if (deja) return res.status(409).json({ error: 'Cet email est déjà pris.' });
    d.email = mail;
  }
  const sets = [];
  const vals = [];
  if (d.email !== undefined) { vals.push(d.email); sets.push(`email = $${vals.length}`); }
  if (d.nom !== undefined) { vals.push(d.nom); sets.push(`nom = $${vals.length}`); }
  if (d.tel !== undefined) { vals.push(d.tel.trim()); sets.push(`tel = $${vals.length}`); }
  if (d.password !== undefined) {
    vals.push(await bcrypt.hash(d.password, 10));
    sets.push(`password_hash = $${vals.length}`);
  }
  if (sets.length) {
    vals.push(req.user.sub);
    await q(`UPDATE users SET ${sets.join(', ')} WHERE id = $${vals.length}`, vals);
  }
  const vSets = [];
  const vVals = [];
  if (d.nom !== undefined) { vVals.push(d.nom); vSets.push(`nom = $${vVals.length}`); }
  if (d.tel !== undefined) { vVals.push(d.tel.trim()); vSets.push(`tel = $${vVals.length}`); }
  if (d.adresse !== undefined) { vVals.push(d.adresse.trim()); vSets.push(`adresse = $${vVals.length}`); }
  if (d.wilaya !== undefined) { vVals.push(d.wilaya.trim()); vSets.push(`wilaya = $${vVals.length}`); }
  if (vSets.length) {
    vVals.push(req.user.sub);
    await q(`UPDATE voyageurs SET ${vSets.join(', ')} WHERE user_id = $${vVals.length}`, vVals);
  }
  await q(`INSERT INTO audit_log (user_id, action, entite, entite_id, details)
           VALUES ($1,'update','profil',$1,$2)`,
    [req.user.sub, JSON.stringify({
      champs: Object.keys(d).filter((k) => k !== 'password'),
      mdp_change: d.password !== undefined,
    })]);
  const u = (await q(`
    SELECT u.id, u.email, u.nom, u.role, u.tel,
           (u.photo IS NOT NULL) AS a_photo,
           v.id IS NOT NULL AS est_voyageur, v.adresse, v.wilaya
    FROM users u LEFT JOIN voyageurs v ON v.user_id = u.id
    WHERE u.id = $1`, [req.user.sub])).rows[0];
  res.json(u);
});

authRouter.post('/moi/photo', requireAuth, async (req, res) => {
  const parsed = z.object({
    data: z.string().min(10).max(4_200_000),
    mime: z.enum(['image/jpeg', 'image/png', 'image/webp']),
  }).safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Photo invalide (JPEG/PNG/WebP, 3 Mo max).' });
  }
  let bytes;
  try { bytes = Buffer.from(parsed.data.data, 'base64'); }
  catch { return res.status(400).json({ error: 'Photo illisible.' }); }
  if (bytes.length > 3_000_000) {
    return res.status(400).json({ error: 'Photo trop lourde (3 Mo max).' });
  }
  await q('UPDATE users SET photo = $1, photo_mime = $2 WHERE id = $3',
    [bytes, parsed.data.mime, req.user.sub]);
  res.json({ ok: true });
});

authRouter.get('/moi/photo', requireAuth, async (req, res) => {
  const u = (await q('SELECT photo, photo_mime FROM users WHERE id = $1',
    [req.user.sub])).rows[0];
  if (!u?.photo) return res.status(404).json({ error: 'Pas de photo.' });
  res.set('Content-Type', u.photo_mime || 'image/jpeg');
  res.send(u.photo);
});

authRouter.get('/photo/:userId', requireAuth, async (req, res) => {
  const id = Number(req.params.userId);
  if (!Number.isInteger(id)) return res.status(400).json({ error: 'Identifiant invalide.' });
  const u = (await q('SELECT photo, photo_mime FROM users WHERE id = $1', [id])).rows[0];
  if (!u?.photo) return res.status(404).json({ error: 'Pas de photo.' });
  res.set('Content-Type', u.photo_mime || 'image/jpeg');
  res.send(u.photo);
});
