export const SQL_NON_DECLARE = '(v.est_admin OR v.sans_carte)';

export function tauxParallele(reglages, devise, secours) {
  const t = Number(devise === 'EUR' ? reglages.taux_parallele_eur : reglages.taux_parallele_usd);
  return Number.isFinite(t) && t > 0 ? t : secours;
}

export function taxesArrivee(baseDevise, reglages, marge30) {
  const ca = baseDevise * Number(reglages.taux_officiel);
  const douane = ca * 0.05;
  const ifu = (ca + douane) * (marge30 ? 1.3 : 1) * 0.005;
  return Math.round(douane + ifu);
}

export function marge30De(ifuMarge, reglages) {
  return ifuMarge == null ? Number(reglages.ifu_marge_30 ?? 1) > 0 : !!ifuMarge;
}

export function basePrevision(marchDevise, declare, reglages) {
  const pct = Number(reglages.frais_carte_pct || 0) / 100;
  return declare > 0 ? declare : marchDevise * (1 - pct);
}

export function fraisMission(m, pocheDA = 0, taxesCarteDA = 0, resteDA = 0) {
  return Number(m.billet) + Number(m.dem_cout) + Number(m.frais_visa || 0) +
    Math.max(0, (pocheDA > 0 ? pocheDA : Number(m.jours) * Number(m.budget_jour)) - resteDA) +
    Number(m.douane) + taxesCarteDA + Number(m.autres) + Number(m.manques_da || 0) +
    (m.valise_sup ? Number(m.valise_sup_prix || 0) : 0) +
    Number(m.saisie_da || 0) + Number(m.frais_taxi || 0) +
    Number(m.part_sejour_calc || 0);
}

export function capaciteMission(m) {
  return Number(m.kg_soute) +
    (m.valise_sup ? Number(m.valise_sup_kg || 23) : 0) +
    (m.bagage_main ? Number(m.bagage_main_kg || 8) : 0);
}

export function douaneMission(m, reglages) {
  if (m.non_declare) return 0;
  if (m.taxes_reelles != null) return Number(m.taxes_reelles);
  if (m.statut === 'cloturee') return Number(m.douane);
  return taxesArrivee(
    basePrevision(Number(m.marchandise_devise || 0), Number(m.declare_total || 0), reglages),
    reglages, true);
}

export function taxesCarteMission(m, reglages) {
  if (m.non_declare) return 0;
  const md = Number(m.marchandise_da || 0), mdev = Number(m.marchandise_devise || 0);
  const tMoyen = mdev > 0 ? md / mdev : Number(reglages.taux_officiel);
  const tPar = tauxParallele(reglages, m.devise_compte, tMoyen);
  const pct = Number(reglages.frais_carte_pct || 0) / 100;
  return m.statut === 'cloturee' && m.factures_total != null
    ? Math.round(Number(m.factures_total) * pct * tPar)
    : Math.round(mdev * pct * tPar);
}

export function manqueUnitaireDA(ligne, reglages) {
  return String(ligne.manque_devise) === 'DA'
    ? Number(ligne.manque_da || 0)
    : Number(ligne.manque_rmb || 0) * Number(reglages.taux_rmb || 0);
}
