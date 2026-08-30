import { Router } from 'express';
import { q } from './db.js';
import { requireAuth, requireRole } from './auth.js';

export const REGLAGES_DEFAUT = {
  comm_pct_defaut: 12,
  frais_carte_pct: 2,
  prix_premiere: 15000,
  prix_renouvellement: 5000,
  prix_visa_double: 8000,
  frais_depot_visa: 6800,
  budget_jour_defaut: 3000,
  taux_officiel: 135,
  ifu_marge_30: 1,
  taux_parallele_usd: 250,
  taux_parallele_eur: 270,
  taux_rmb: 35,
  objectif_devises_usd: 2000,
  seuil_passeport_mois: 8,
  seuil_autorisation_jours: 60
};

export async function getReglages() {
  const row = (await q('SELECT data FROM reglages WHERE id = 1')).rows[0];
  return { ...REGLAGES_DEFAUT, ...(row?.data ?? {}) };
}

export const reglagesRouter = Router();
reglagesRouter.use(requireAuth, requireRole('admin', 'voyageur'));

reglagesRouter.get('/', async (_req, res) => res.json(await getReglages()));

let tauxLive = null;
export async function coursOfficiels() {
  if (tauxLive && Date.now() - tauxLive.quand < 12 * 3600 * 1000) return tauxLive;
  const r = await fetch('https://open.er-api.com/v6/latest/USD', { signal: AbortSignal.timeout(8000) });
  const j = await r.json();
  const dzd = Number(j?.rates?.DZD), cny = Number(j?.rates?.CNY);
  if (!Number.isFinite(dzd) || dzd <= 0) throw new Error('indisponible');
  tauxLive = {
    valeur: Math.round(dzd * 100) / 100,
    cny: Number.isFinite(cny) && cny > 0 ? Math.round(cny * 100) / 100 : 0,
    date: j.time_last_update_utc ?? '', quand: Date.now(),
  };
  return tauxLive;
}

reglagesRouter.get('/taux-usd', async (_req, res) => {
  try {
    res.json(await coursOfficiels());
  } catch {
    res.status(502).json({ error: 'Cours USD/DZD indisponible pour le moment — saisis-le à la main.' });
  }
});

reglagesRouter.put('/', async (req, res) => {
  const clean = {};
  for (const k of Object.keys(REGLAGES_DEFAUT)) {
    const v = Number(req.body?.[k]);
    if (Number.isFinite(v) && v >= 0) clean[k] = v;
  }
  await q('UPDATE reglages SET data = $1 WHERE id = 1', [JSON.stringify(clean)]);
  res.json({ ...REGLAGES_DEFAUT, ...clean });
});
