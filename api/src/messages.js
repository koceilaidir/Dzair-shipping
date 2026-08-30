import { Router } from 'express';
import { z } from 'zod';
import { q } from './db.js';
import { requireAuth } from './auth.js';

export const messagesRouter = Router();
messagesRouter.use(requireAuth);

messagesRouter.get('/contacts', async (req, res) => {
  const moi = req.user.sub;
  const { rows } = await q(`
    SELECT u.id, u.nom, u.role,
           d.texte  AS dernier_texte,
           d.created_at AS dernier_date,
           d.de_user = u.id AS dernier_recu,
           COALESCE(nl.n, 0) AS non_lus
    FROM users u
    LEFT JOIN LATERAL (
      SELECT texte, created_at, de_user FROM messages
      WHERE (de_user = u.id AND a_user = $1) OR (de_user = $1 AND a_user = u.id)
      ORDER BY created_at DESC, id DESC LIMIT 1
    ) d ON TRUE
    LEFT JOIN (
      SELECT de_user, COUNT(*) AS n FROM messages
      WHERE a_user = $1 AND lu = FALSE GROUP BY de_user
    ) nl ON nl.de_user = u.id
    WHERE u.actif = TRUE AND u.id <> $1
    ORDER BY d.created_at DESC NULLS LAST, u.nom`, [moi]);
  res.json(rows.map((r) => ({
    id: r.id, nom: r.nom, role: r.role,
    dernier_texte: r.dernier_texte, dernier_date: r.dernier_date,
    dernier_recu: r.dernier_recu === true, non_lus: Number(r.non_lus),
  })));
});

messagesRouter.get('/avec/:userId', async (req, res) => {
  const autre = Number(req.params.userId);
  if (!Number.isInteger(autre)) return res.status(400).json({ error: 'Identifiant invalide.' });
  const moi = req.user.sub;
  const { rows } = await q(`
    SELECT id, de_user, a_user, texte, lu, created_at FROM messages
    WHERE (de_user = $1 AND a_user = $2) OR (de_user = $2 AND a_user = $1)
    ORDER BY created_at DESC, id DESC LIMIT 200`, [moi, autre]);

  await q('UPDATE messages SET lu = TRUE WHERE de_user = $1 AND a_user = $2 AND lu = FALSE',
    [autre, moi]);
  res.json(rows.reverse().map((m) => ({
    id: m.id, de_moi: m.de_user === moi, texte: m.texte, lu: m.lu, date: m.created_at,
  })));
});

messagesRouter.post('/avec/:userId', async (req, res) => {
  const autre = Number(req.params.userId);
  if (!Number.isInteger(autre)) return res.status(400).json({ error: 'Identifiant invalide.' });
  const parsed = z.object({ texte: z.string().trim().min(1).max(4000) }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'Message vide ou trop long.' });
  const dest = (await q('SELECT id FROM users WHERE id = $1 AND actif = TRUE', [autre])).rows[0];
  if (!dest) return res.status(404).json({ error: 'Destinataire introuvable.' });
  const { rows } = await q(
    `INSERT INTO messages (de_user, a_user, texte) VALUES ($1,$2,$3)
     RETURNING id, texte, created_at`,
    [req.user.sub, autre, parsed.data.texte]);
  res.status(201).json({ id: rows[0].id, de_moi: true, texte: rows[0].texte,
    lu: false, date: rows[0].created_at });
});

messagesRouter.get('/non-lus', async (req, res) => {
  const { rows } = await q(
    'SELECT COUNT(*) AS n FROM messages WHERE a_user = $1 AND lu = FALSE', [req.user.sub]);
  res.json({ total: Number(rows[0].n) });
});
