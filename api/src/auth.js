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
});

authRouter.post('/login', loginLimiter, async (req, res) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Requête invalide.' });

  const { email, password } = parsed.data;
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
    { expiresIn: process.env.JWT_EXPIRES || '12h' },
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
  const u = (await q(
    'SELECT id, email, nom, role, tel FROM users WHERE id = $1', [req.user.sub])).rows[0];
  if (!u) return res.status(404).json({ error: 'Compte introuvable.' });
  res.json(u);
});

authRouter.put('/moi', requireAuth, async (req, res) => {
  const parsed = z.object({ tel: z.string().max(40).optional().default('') }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Données invalides.' });
  const { rows } = await q(
    'UPDATE users SET tel = $1 WHERE id = $2 RETURNING id, email, nom, role, tel',
    [parsed.data.tel.trim(), req.user.sub]);
  res.json(rows[0]);
});
