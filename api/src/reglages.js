import { Router } from 'express';
import { q } from './db.js';
import { requireAuth, requireRole } from './auth.js';

/** Valeurs par défaut — modifiables dans l'écran Réglages. */
export const REGLAGES_DEFAUT = {
  comm_pct_defaut: 12,         // commission voyageur par défaut (% du bénéfice)
  frais_carte_pct: 2,          // frais de carte BEA (% des paiements)
  prix_premiere: 15000,        // première demande (DA)
  prix_renouvellement: 5000,   // renouvellement (DA)
  prix_visa_double: 8000,      // visa double entrée (DA)
  frais_depot_visa: 6800,      // frais de dépôt du visa (DA)
  budget_jour_defaut: 3000,    // argent de poche par jour (DA)
  taux_officiel: 135,          // DA / USD — pour la douane à l'arrivée
  ifu_marge_30: 1,             // 1 = la douane ajoute sa marge de 30 % avant l'IFU (ajustable à la clôture)
  taux_parallele_usd: 250,     // DA / USD au marché parallèle — coût réel des taxes de carte
  taux_parallele_eur: 270,     // DA / EUR au marché parallèle
  taux_rmb: 35,                // DA / RMB — pour valoriser les manques (pièces perdues)
  objectif_devises_usd: 2000,  // à déposer dans le compte BEA par voyage
  seuil_passeport_mois: 8,     // alerte X mois avant péremption du passeport
  seuil_autorisation_jours: 60 // alerte X jours avant expiration de l'autorisation
};

export async function getReglages() {
  const row = (await q('SELECT data FROM reglages WHERE id = 1')).rows[0];
  return { ...REGLAGES_DEFAUT, ...(row?.data ?? {}) };
}

export const reglagesRouter = Router();
reglagesRouter.use(requireAuth, requireRole('admin'));

reglagesRouter.get('/', async (_req, res) => res.json(await getReglages()));

// Cours OFFICIELS du jour (open.er-api.com, gratuit, sans clé) — cache 12 h.
// USD/DZD pour le taux officiel, USD/CNY pour convertir les manques ¥ → $.
let tauxLive = null; // { valeur (DZD), cny (CNY pour 1 USD), date, quand }
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
