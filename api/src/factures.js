import { Router } from 'express';
import { z } from 'zod';
import PDFDocument from 'pdfkit';
import { q } from './db.js';
import { requireAuth, requireRole } from './auth.js';

/* Factures des valises — émises au nom de la société de facturation, tout en
   chinois sauf les noms de produits (anglais). Figées à la génération. */
export const facturesRouter = Router();
facturesRouter.use(requireAuth, requireRole('admin'));

const FONT = new URL('../fonts/NotoSansSC-Regular.otf', import.meta.url).pathname;
const FONT_B = new URL('../fonts/NotoSansSC-Bold.otf', import.meta.url).pathname;

const audit = (userId, action, entite, id, details) => q(
  `INSERT INTO audit_log (user_id, action, entite, entite_id, details) VALUES ($1,$2,$3,$4,$5)`,
  [userId, action, entite, id, JSON.stringify(details)]);

/* ---------- Helpers ---------- */
const dateCn = (d) => {
  const s = new Date(d).toISOString().slice(0, 10);
  return `${s.slice(0, 4)}年${s.slice(5, 7)}月${s.slice(8, 10)}日`;
};
const money = (n) => Number(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

// Montant en toutes lettres (大写) pour des dollars US : 壹仟肆佰捌拾贰美元整
const CN_DIG = '零壹贰叁肆伍陆柒捌玖';
function daxie(n) {
  const yuan = Math.floor(n + 1e-9);
  const cents = Math.round((n - yuan) * 100);
  const units = ['', '拾', '佰', '仟'];
  const big = ['', '万', '亿'];
  const seg = (v) => { // 0-9999 → 大写
    let s = '', zero = false;
    for (let i = 3; i >= 0; i--) {
      const d = Math.floor(v / 10 ** i) % 10;
      if (d === 0) { if (s) zero = true; }
      else { s += (zero ? '零' : '') + CN_DIG[d] + units[i]; zero = false; }
    }
    return s;
  };
  let out = '';
  if (yuan === 0) out = '零';
  else {
    let v = yuan, i = 0, parts = [];
    while (v > 0) { const p = v % 10000; parts.unshift(p ? seg(p) + big[i] : ''); v = Math.floor(v / 10000); i++; }
    out = parts.join('').replace(/零+/g, '零').replace(/零$/, '');
  }
  out += '美元';
  if (cents === 0) return out + '整';
  const j = Math.floor(cents / 10), f = cents % 10;
  return out + (j ? CN_DIG[j] + '角' : '') + (f ? CN_DIG[f] + '分' : '');
}

async function factureComplete(id) {
  return (await q(
    `SELECT f.*, m.code AS mission_code, v.nom AS voyageur
     FROM factures f JOIN missions m ON m.id = f.mission_id JOIN voyageurs v ON v.id = m.voyageur_id
     WHERE f.id = $1`, [id])).rows[0];
}

/* ---------- Liste par mission ---------- */
facturesRouter.get('/', async (req, res) => {
  const mid = Number(req.query.mission);
  if (!mid) return res.status(400).json({ error: 'mission requise.' });
  const { rows } = await q(
    `SELECT * FROM factures WHERE mission_id = $1 AND statut = 'emise' ORDER BY date, id`, [mid]);
  res.json(rows);
});

/* ---------- Génération : un groupe = une facture ----------
   body : { mission_id, taux_rmb, groupes: [{ affectation_ids: [..], date?: 'YYYY-MM-DD' }] } */
facturesRouter.post('/generer', async (req, res) => {
  const p = z.object({
    mission_id: z.coerce.number().int(),
    taux_rmb: z.coerce.number().positive(),
    groupes: z.array(z.object({
      affectation_ids: z.array(z.coerce.number().int()).min(1),
      date: z.string().max(10).optional(),
    })).min(1),
  }).safeParse(req.body);
  if (!p.success) return res.status(400).json({ error: 'Données invalides (taux RMB et au moins un groupe).' });
  const d = p.data;

  const m = (await q(
    `SELECT m.*, v.nom, v.nom_passeport, v.tel, v.adresse, v.wilaya
     FROM missions m JOIN voyageurs v ON v.id = m.voyageur_id WHERE m.id = $1`, [d.mission_id])).rows[0];
  if (!m) return res.status(404).json({ error: 'Mission introuvable.' });
  if (m.statut === 'cloturee') return res.status(409).json({ error: 'Mission clôturée — factures figées.' });
  const soc = (await q(
    'SELECT * FROM societes_facturation ORDER BY par_defaut DESC, id LIMIT 1')).rows[0];
  if (!soc) return res.status(409).json({ error: 'Renseigne d’abord la société de facturation (Réglages).' });

  // Affectations SOUTE de la mission (avec prix déclaré) — le bagage à main n'est
  // JAMAIS facturé ni déclaré ; chaque groupe doit en prendre.
  const aff = (await q(
    `SELECT a.id, a.quantite, a.prix_declare, l.produit
     FROM affectations a JOIN bon_lignes l ON l.id = a.ligne_id
     WHERE a.mission_id = $1 AND a.emplacement = 'soute'`, [d.mission_id])).rows;
  const byId = new Map(aff.map((a) => [a.id, a]));
  const deja = new Set((await q(
    `SELECT jsonb_array_elements(lignes)->>'affectation_id' AS aid FROM factures
     WHERE mission_id = $1 AND statut = 'emise'`, [d.mission_id])).rows.map((r) => Number(r.aid)));

  // Dates : une différente par facture, entre le départ et la veille du retour.
  const dep = m.depart ? new Date(m.depart) : new Date();
  const ret = m.retour ? new Date(m.retour) : new Date(dep.getTime() + 5 * 86400000);
  const span = Math.max(1, Math.round((ret - dep) / 86400000) - 1);
  const dateAuto = (i, n) => {
    const step = span / Math.max(1, n);
    const off = Math.min(span - 1, Math.floor(step * i + step / 2));
    return new Date(dep.getTime() + Math.max(0, off) * 86400000).toISOString().slice(0, 10);
  };

  const client = {
    nom: (m.nom_passeport && m.nom_passeport.trim()) ? m.nom_passeport.trim() : m.nom,
    tel: m.tel || '',
    adresse: [m.adresse, m.wilaya, 'Algeria'].filter((x) => x && String(x).trim()).join(', '),
  };
  const socJson = {
    nom_cn: soc.nom_cn, nom_en: soc.nom_en, code_credit: soc.code_credit,
    adresse_cn: soc.adresse_cn, adresse_en: soc.adresse_en, tel: soc.tel, email: soc.email,
  };

  const created = [];
  for (let gi = 0; gi < d.groupes.length; gi++) {
    const g = d.groupes[gi];
    const lignes = [];
    for (const aid of g.affectation_ids) {
      const a = byId.get(aid);
      if (!a) return res.status(400).json({ error: `Produit ${aid} introuvable dans cette valise.` });
      if (deja.has(aid)) return res.status(409).json({ error: `« ${a.produit} » est déjà sur une facture émise.` });
      if (!a.prix_declare || Number(a.prix_declare) <= 0) {
        return res.status(409).json({ error: `Prix déclaré manquant pour « ${a.produit} ».` });
      }
      const qte = Number(a.quantite), prix = Number(a.prix_declare);
      lignes.push({ affectation_id: aid, produit: a.produit, quantite: qte, prix, montant: Math.round(qte * prix * 100) / 100 });
      deja.add(aid);
    }
    const total = Math.round(lignes.reduce((s, l) => s + l.montant, 0) * 100) / 100;
    const totalRmb = Math.round(total * d.taux_rmb * 100) / 100;
    const numero = Math.floor(Math.random() * 31); // 0..30
    const date = g.date || dateAuto(gi, d.groupes.length);
    const { rows } = await q(
      `INSERT INTO factures (mission_id, societe_id, numero, date, client_nom, client_tel, client_adresse,
         devise, taux_rmb, total, total_rmb, lignes, societe)
       VALUES ($1,$2,$3,$4,$5,$6,$7,'USD',$8,$9,$10,$11,$12) RETURNING *`,
      [d.mission_id, soc.id, numero, date, client.nom, client.tel, client.adresse,
       d.taux_rmb, total, totalRmb, JSON.stringify(lignes), JSON.stringify(socJson)]);
    created.push(rows[0]);
  }
  await audit(req.user.sub, 'factures', 'mission', d.mission_id,
    { code: m.code, voyageur: m.nom, nb: created.length, total: created.reduce((s, f) => s + Number(f.total), 0) });
  res.status(201).json(created);
});

/* ---------- Annuler (mission non clôturée) ---------- */
facturesRouter.delete('/:id', async (req, res) => {
  const f = await factureComplete(Number(req.params.id));
  if (!f) return res.status(404).json({ error: 'Facture introuvable.' });
  const m = (await q('SELECT statut FROM missions WHERE id = $1', [f.mission_id])).rows[0];
  if (m?.statut === 'cloturee') return res.status(409).json({ error: 'Mission clôturée — factures figées.' });
  await q(`UPDATE factures SET statut = 'annulee' WHERE id = $1`, [f.id]);
  await audit(req.user.sub, 'facture_annulee', 'mission', f.mission_id, { code: f.mission_code, numero: f.numero });
  res.json({ ok: true });
});

/* ---------- PDF ---------- */
function dessiner(doc, f) {
  const soc = f.societe || {};
  const W = doc.page.width, L = 50, R = W - 50, CW = R - L;
  doc.font(FONT_B).fontSize(20).text(soc.nom_cn || '', L, 56, { width: CW, align: 'center' });
  doc.font(FONT).fontSize(10.5).text(soc.nom_en || '', { width: CW, align: 'center' });
  doc.moveDown(0.6);
  doc.fontSize(10.5)
    .text(`统一社会信用代码：${soc.code_credit || ''}`, { width: CW, align: 'center' })
    .text(`地址：${soc.adresse_cn || ''}${soc.tel ? `    电话：${soc.tel}` : ''}`, { width: CW, align: 'center' });
  doc.moveDown(0.8);
  doc.font(FONT_B).fontSize(16).text('销 售 发 票', { width: CW, align: 'center' });
  doc.moveDown(0.8);

  // Bloc infos
  doc.font(FONT).fontSize(10.5);
  let y = doc.y;
  const col2 = L + CW / 2;
  const kv = (x, k, v) => { doc.text(k, x, y, { continued: true }); doc.font(FONT).text(v); };
  kv(L, '发票编号：', String(f.numero)); doc.text(`开票日期：${dateCn(f.date)}`, col2, y); y += 17;
  doc.text(`客户姓名：${f.client_nom}`, L, y); doc.text(`电话：${f.client_tel || '—'}`, col2, y); y += 17;
  doc.text(`客户地址：${f.client_adresse || '—'}`, L, y, { width: CW }); y = doc.y + 3;
  doc.text('币种：美元 (USD)', L, y); y += 22;

  // Tableau
  const cols = [34, CW - 34 - 60 - 90 - 100, 60, 90, 100];
  const xs = [L]; for (let i = 0; i < cols.length - 1; i++) xs.push(xs[i] + cols[i]);
  const heads = ['序号', '产品名称', '数量', '单价 (USD)', '金额 (USD)'];
  const rowH = 24;
  const cell = (i, txt, yy, bold = false, align = 'left') => {
    doc.font(bold ? FONT_B : FONT).fontSize(10.5)
      .text(txt, xs[i] + 6, yy + 7, { width: cols[i] - 12, align, lineBreak: false });
  };
  const gridRow = (yy) => { for (let i = 0; i <= cols.length; i++) { const x = i < cols.length ? xs[i] : R; doc.moveTo(x, yy).lineTo(x, yy + rowH).stroke(); } doc.moveTo(L, yy).lineTo(R, yy).stroke(); };
  doc.lineWidth(0.8);
  gridRow(y); heads.forEach((h, i) => cell(i, h, y, true, 'center')); y += rowH;
  const lignes = Array.isArray(f.lignes) ? f.lignes : JSON.parse(f.lignes || '[]');
  let qteTot = 0;
  lignes.forEach((l, k) => {
    gridRow(y);
    cell(0, String(k + 1), y, false, 'center');
    cell(1, l.produit, y);
    cell(2, String(Number(l.quantite)), y, false, 'center');
    cell(3, money(l.prix), y, false, 'right');
    cell(4, money(l.montant), y, false, 'right');
    qteTot += Number(l.quantite); y += rowH;
  });
  gridRow(y); cell(1, '合计', y, true); cell(2, String(qteTot), y, true, 'center'); cell(4, money(f.total), y, true, 'right'); y += rowH;
  doc.moveTo(L, y).lineTo(R, y).stroke();

  // Totaux
  y += 12;
  doc.font(FONT).fontSize(10.5)
    .text(`合计金额（大写）：${daxie(Number(f.total))}    （小写）：USD ${money(f.total)}`, L, y, { width: CW });
  y = doc.y + 4;
  doc.text(`汇率：1 USD = ${Number(f.taux_rmb).toFixed(2)} RMB    合计（人民币）：RMB ${money(f.total_rmb)}`, L, y, { width: CW });

  // Signature
  y = doc.y + 40;
  doc.text(`收款单位（盖章）：${soc.nom_cn || ''}`, L, y);
  doc.text('开票人：', R - 120, y);
}

function envoyerPdf(res, nom, dessine) {
  const doc = new PDFDocument({ size: 'A4', margin: 50, autoFirstPage: false, info: { Title: nom } });
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="${nom}"`);
  doc.pipe(res);
  dessine(doc);
  doc.end();
}

facturesRouter.get('/:id/pdf', async (req, res) => {
  const f = await factureComplete(Number(req.params.id));
  if (!f) return res.status(404).json({ error: 'Facture introuvable.' });
  envoyerPdf(res, `facture-${f.mission_code}-${f.numero}.pdf`, (doc) => { doc.addPage(); dessiner(doc, f); });
});

facturesRouter.get('/mission/:id/pdf', async (req, res) => {
  const mid = Number(req.params.id);
  const { rows } = await q(
    `SELECT f.*, m.code AS mission_code FROM factures f JOIN missions m ON m.id = f.mission_id
     WHERE f.mission_id = $1 AND f.statut = 'emise' ORDER BY f.date, f.id`, [mid]);
  if (!rows.length) return res.status(404).json({ error: 'Aucune facture.' });
  envoyerPdf(res, `factures-${rows[0].mission_code}.pdf`, (doc) => {
    for (const f of rows) { doc.addPage(); dessiner(doc, f); }
  });
});
