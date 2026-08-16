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

reglagesRouter.put('/', async (req, res) => {
  const clean = {};
  for (const k of Object.keys(REGLAGES_DEFAUT)) {
    const v = Number(req.body?.[k]);
    if (Number.isFinite(v) && v >= 0) clean[k] = v;
  }
  await q('UPDATE reglages SET data = $1 WHERE id = 1', [JSON.stringify(clean)]);
  res.json({ ...REGLAGES_DEFAUT, ...clean });
});
