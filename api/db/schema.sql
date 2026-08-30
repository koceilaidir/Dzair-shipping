CREATE TABLE IF NOT EXISTS users (
  id            SERIAL PRIMARY KEY,
  email         TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role          TEXT NOT NULL CHECK (role IN ('admin','voyageur','client')),
  nom           TEXT NOT NULL,
  actif         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS voyageurs (
  id              SERIAL PRIMARY KEY,
  user_id         INTEGER REFERENCES users(id),
  nom             TEXT NOT NULL,
  tel             TEXT,
  comm_mode       TEXT NOT NULL DEFAULT 'kg' CHECK (comm_mode IN ('kg','pct','fixe')),
  comm_val        NUMERIC(12,2) NOT NULL DEFAULT 0,
  bagages         INTEGER NOT NULL DEFAULT 2,
  depuis          TEXT,
  dette_active    BOOLEAN NOT NULL DEFAULT FALSE,
  dette_montant   NUMERIC(14,2) NOT NULL DEFAULT 0,
  dette_rembourse NUMERIC(14,2) NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS missions (
  id              SERIAL PRIMARY KEY,
  voyageur_id     INTEGER NOT NULL REFERENCES voyageurs(id),
  code            TEXT NOT NULL UNIQUE,
  vol             TEXT,
  depart          DATE,
  retour          DATE,
  heure_decollage TIMESTAMPTZ,
  duree_vol_min   INTEGER,
  jours           INTEGER NOT NULL DEFAULT 5,
  budget_jour     NUMERIC(12,2) NOT NULL DEFAULT 3000,
  billet          NUMERIC(12,2) NOT NULL DEFAULT 0,
  dem_type        TEXT NOT NULL DEFAULT 'multiple'
                    CHECK (dem_type IN ('premiere','renouvellement','visa_double','multiple')),
  dem_cout        NUMERIC(12,2) NOT NULL DEFAULT 0,
  bea             NUMERIC(12,2) NOT NULL DEFAULT 0,
  douane          NUMERIC(12,2) NOT NULL DEFAULT 0,
  autres          NUMERIC(12,2) NOT NULL DEFAULT 0,
  objectif        NUMERIC(12,2) NOT NULL DEFAULT 20000,
  kg_soute        NUMERIC(6,2)  NOT NULL DEFAULT 46,
  cabine          BOOLEAN NOT NULL DEFAULT FALSE,
  val_declaree    NUMERIC(14,2),
  statut          TEXT NOT NULL DEFAULT 'planifiee'
                    CHECK (statut IN ('planifiee','encours','cloturee','annulee')),
  depot           TEXT,
  attendu         NUMERIC(14,2),
  primes          NUMERIC(12,2) NOT NULL DEFAULT 0,
  invendus        TEXT,
  cloture_date    DATE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS produits_mission (
  id         SERIAL PRIMARY KEY,
  mission_id INTEGER NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
  nom        TEXT NOT NULL,
  kg         NUMERIC(8,2)  NOT NULL,
  prix_kg    NUMERIC(12,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS paiements (
  id         SERIAL PRIMARY KEY,
  mission_id INTEGER NOT NULL REFERENCES missions(id),
  date       DATE NOT NULL DEFAULT CURRENT_DATE,
  montant    NUMERIC(14,2) NOT NULL,
  note       TEXT
);

CREATE TABLE IF NOT EXISTS tranches_devises (
  id          SERIAL PRIMARY KEY,
  voyageur_id INTEGER NOT NULL REFERENCES voyageurs(id),
  mission_id  INTEGER REFERENCES missions(id),
  usd         NUMERIC(12,2) NOT NULL,
  taux        NUMERIC(8,2)  NOT NULL,
  date        DATE NOT NULL DEFAULT CURRENT_DATE,
  source      TEXT,
  motif       TEXT NOT NULL DEFAULT 'voyage' CHECK (motif IN ('voyage','depot_bloque'))
);

CREATE TABLE IF NOT EXISTS remboursements_dette (
  id          SERIAL PRIMARY KEY,
  voyageur_id INTEGER NOT NULL REFERENCES voyageurs(id),
  date        DATE NOT NULL DEFAULT CURRENT_DATE,
  montant     NUMERIC(14,2) NOT NULL,
  devise      TEXT NOT NULL DEFAULT 'DA' CHECK (devise IN ('DA','USD')),
  taux        NUMERIC(8,2)
);

CREATE TABLE IF NOT EXISTS audit_log (
  id         SERIAL PRIMARY KEY,
  user_id    INTEGER REFERENCES users(id),
  action     TEXT NOT NULL,
  entite     TEXT NOT NULL,
  entite_id  INTEGER,
  details    JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE missions ADD COLUMN IF NOT EXISTS comm_mode  TEXT;
ALTER TABLE missions ADD COLUMN IF NOT EXISTS comm_val   NUMERIC(12,2);
ALTER TABLE missions ADD COLUMN IF NOT EXISTS commission NUMERIC(14,2);

CREATE TABLE IF NOT EXISTS historique_commissions (
  id            SERIAL PRIMARY KEY,
  voyageur_id   INTEGER NOT NULL REFERENCES voyageurs(id),
  ancien_mode   TEXT,
  ancienne_val  NUMERIC(12,2),
  nouveau_mode  TEXT,
  nouvelle_val  NUMERIC(12,2),
  user_id       INTEGER REFERENCES users(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS passeport_expire    DATE;
ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS autorisation_expire DATE;
ALTER TABLE tranches_devises ADD COLUMN IF NOT EXISTS devise TEXT NOT NULL DEFAULT 'USD';
ALTER TABLE missions ADD COLUMN IF NOT EXISTS check_depart JSONB NOT NULL DEFAULT '{}';
ALTER TABLE missions ADD COLUMN IF NOT EXISTS check_retour JSONB NOT NULL DEFAULT '{}';

CREATE TABLE IF NOT EXISTS reglages (
  id   INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  data JSONB NOT NULL DEFAULT '{}'
);
INSERT INTO reglages (id, data) VALUES (1, '{}') ON CONFLICT (id) DO NOTHING;

ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS devise_compte       TEXT NOT NULL DEFAULT 'USD';
ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS allocation_eligible BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS allocation_derniere DATE;
ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS solde_devises       NUMERIC(14,2) NOT NULL DEFAULT 0;
ALTER TABLE missions  ADD COLUMN IF NOT EXISTS frais_visa          NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE missions  ADD COLUMN IF NOT EXISTS allocation_utilisee BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE missions  ADD COLUMN IF NOT EXISTS factures_total      NUMERIC(14,2);
ALTER TABLE missions  ADD COLUMN IF NOT EXISTS heure_depart        TEXT;
ALTER TABLE missions  ADD COLUMN IF NOT EXISTS heure_arrivee       TEXT;

ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS statut_dispo TEXT NOT NULL DEFAULT 'disponible'
  CHECK (statut_dispo IN ('disponible','indisponible','limite'));
ALTER TABLE missions ADD COLUMN IF NOT EXISTS poche_mode TEXT NOT NULL DEFAULT 'cash_da'
  CHECK (poche_mode IN ('cash_da','rmb_alipay','cash_devise','carte'));
ALTER TABLE missions ADD COLUMN IF NOT EXISTS poche_frais_carte NUMERIC(12,2) NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS demandes_suppression (
  id          SERIAL PRIMARY KEY,
  mission_id  INTEGER NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
  demandeur   INTEGER NOT NULL REFERENCES users(id),
  approbateurs JSONB NOT NULL DEFAULT '[]',
  statut      TEXT NOT NULL DEFAULT 'en_attente' CHECK (statut IN ('en_attente','approuvee','rejetee')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE tranches_devises DROP CONSTRAINT IF EXISTS tranches_devises_motif_check;
ALTER TABLE tranches_devises ADD CONSTRAINT tranches_devises_motif_check
  CHECK (motif IN ('voyage','depot_bloque','poche'));

ALTER TABLE missions ADD COLUMN IF NOT EXISTS valise_close BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS chambres (
  id            SERIAL PRIMARY KEY,
  nom           TEXT NOT NULL,
  ville         TEXT NOT NULL DEFAULT 'Canton',
  depot_adresse TEXT,
  depot_wilaya  TEXT,
  note          TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS chambre_contacts (
  id         SERIAL PRIMARY KEY,
  chambre_id INTEGER NOT NULL REFERENCES chambres(id) ON DELETE CASCADE,
  nom        TEXT NOT NULL,
  tel        TEXT,
  role       TEXT
);
CREATE TABLE IF NOT EXISTS bons (
  id         SERIAL PRIMARY KEY,
  chambre_id INTEGER NOT NULL REFERENCES chambres(id),
  date       DATE NOT NULL DEFAULT CURRENT_DATE,
  note       TEXT,
  user_id    INTEGER REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS bon_lignes (
  id          SERIAL PRIMARY KEY,
  bon_id      INTEGER NOT NULL REFERENCES bons(id) ON DELETE CASCADE,
  produit     TEXT NOT NULL,
  quantite    NUMERIC(10,2) NOT NULL,
  poids_total NUMERIC(10,3) NOT NULL,
  manque_rmb  NUMERIC(12,2) NOT NULL DEFAULT 0,
  mode        TEXT NOT NULL DEFAULT 'kg' CHECK (mode IN ('kg','piece')),
  prix        NUMERIC(12,2) NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS affectations (
  id         SERIAL PRIMARY KEY,
  ligne_id   INTEGER NOT NULL REFERENCES bon_lignes(id) ON DELETE CASCADE,
  mission_id INTEGER NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
  quantite   NUMERIC(10,2) NOT NULL,
  manquants  NUMERIC(10,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE missions ADD COLUMN IF NOT EXISTS manques_da NUMERIC(14,2) NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_affect_mission ON affectations(mission_id);
CREATE INDEX IF NOT EXISTS idx_affect_ligne   ON affectations(ligne_id);
CREATE INDEX IF NOT EXISTS idx_bons_chambre   ON bons(chambre_id);

CREATE TABLE IF NOT EXISTS societes_facturation (
  id          SERIAL PRIMARY KEY,
  nom_cn      TEXT NOT NULL,
  nom_en      TEXT NOT NULL DEFAULT '',
  code_credit TEXT NOT NULL DEFAULT '',
  adresse_cn  TEXT NOT NULL DEFAULT '',
  adresse_en  TEXT NOT NULL DEFAULT '',
  tel         TEXT NOT NULL DEFAULT '',
  email       TEXT NOT NULL DEFAULT '',
  devise      TEXT NOT NULL DEFAULT 'USD',
  par_defaut  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO societes_facturation (nom_cn, nom_en, code_credit, adresse_cn, adresse_en, par_defaut)
SELECT '广州觅涅伍贸易有限公司', 'GUANGZHOU MINIEWU TRADING CO., LTD.', '91440106MAK9J26C7Q',
       '广州市天河区天河北路179号12层自编04房562号',
       'Room 562, Self-numbered 04, 12/F, No.179 Tianhe North Road, Tianhe District, Guangzhou', TRUE
WHERE NOT EXISTS (SELECT 1 FROM societes_facturation);

ALTER TABLE affectations ADD COLUMN IF NOT EXISTS prix_declare NUMERIC(12,2);
ALTER TABLE bon_lignes   ADD COLUMN IF NOT EXISTS prix_declare NUMERIC(12,2);

ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS nom_passeport TEXT;
ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS adresse       TEXT;
ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS wilaya        TEXT;

CREATE TABLE IF NOT EXISTS factures (
  id             SERIAL PRIMARY KEY,
  mission_id     INTEGER NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
  societe_id     INTEGER REFERENCES societes_facturation(id),
  numero         INTEGER NOT NULL,
  date           DATE NOT NULL,
  client_nom     TEXT NOT NULL DEFAULT '',
  client_tel     TEXT NOT NULL DEFAULT '',
  client_adresse TEXT NOT NULL DEFAULT '',
  devise         TEXT NOT NULL DEFAULT 'USD',
  taux_rmb       NUMERIC(10,4) NOT NULL DEFAULT 0,
  total          NUMERIC(14,2) NOT NULL DEFAULT 0,
  total_rmb      NUMERIC(14,2) NOT NULL DEFAULT 0,
  lignes         JSONB NOT NULL DEFAULT '[]',
  societe        JSONB NOT NULL DEFAULT '{}',
  statut         TEXT NOT NULL DEFAULT 'emise' CHECK (statut IN ('emise','annulee')),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_factures_mission ON factures(mission_id);

CREATE TABLE IF NOT EXISTS retours (
  id         SERIAL PRIMARY KEY,
  ligne_id   INTEGER NOT NULL REFERENCES bon_lignes(id) ON DELETE CASCADE,
  quantite   NUMERIC(10,2) NOT NULL,
  date       DATE NOT NULL DEFAULT CURRENT_DATE,
  user_id    INTEGER REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_retours_ligne ON retours(ligne_id);

ALTER TABLE missions ADD COLUMN IF NOT EXISTS ifu_marge BOOLEAN;

ALTER TABLE affectations ADD COLUMN IF NOT EXISTS emplacement TEXT NOT NULL DEFAULT 'soute'
  CHECK (emplacement IN ('soute','main'));
ALTER TABLE affectations ADD COLUMN IF NOT EXISTS saisis NUMERIC(10,2) NOT NULL DEFAULT 0;
ALTER TABLE missions ADD COLUMN IF NOT EXISTS valise_sup        BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE missions ADD COLUMN IF NOT EXISTS valise_sup_prix   NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE missions ADD COLUMN IF NOT EXISTS valise_sup_kg     NUMERIC(6,2)  NOT NULL DEFAULT 23;
ALTER TABLE missions ADD COLUMN IF NOT EXISTS bagage_main       BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE missions ADD COLUMN IF NOT EXISTS bagage_main_kg    NUMERIC(6,2)  NOT NULL DEFAULT 8;
ALTER TABLE missions ADD COLUMN IF NOT EXISTS bagage_main_close BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE missions ADD COLUMN IF NOT EXISTS liquide_remis     NUMERIC(14,2);
ALTER TABLE missions ADD COLUMN IF NOT EXISTS taxes_reelles     NUMERIC(14,2);
ALTER TABLE missions ADD COLUMN IF NOT EXISTS arrivee_note      TEXT;
ALTER TABLE missions ADD COLUMN IF NOT EXISTS saisie_da         NUMERIC(14,2) NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS mission_docs (
  id         SERIAL PRIMARY KEY,
  mission_id INTEGER NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
  type       TEXT NOT NULL,
  mime       TEXT NOT NULL DEFAULT 'image/jpeg',
  data       BYTEA NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_mission_docs ON mission_docs(mission_id);

ALTER TABLE tranches_devises DROP CONSTRAINT IF EXISTS tranches_devises_motif_check;
ALTER TABLE tranches_devises ADD CONSTRAINT tranches_devises_motif_check
  CHECK (motif IN ('voyage','depot_bloque','poche','reste'));
ALTER TABLE paiements ADD COLUMN IF NOT EXISTS chambre_id INTEGER REFERENCES chambres(id);
ALTER TABLE paiements ADD COLUMN IF NOT EXISTS user_id    INTEGER REFERENCES users(id);

CREATE TABLE IF NOT EXISTS mission_depots (
  id         SERIAL PRIMARY KEY,
  mission_id INTEGER NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
  chambre_id INTEGER NOT NULL REFERENCES chambres(id),
  statut     TEXT NOT NULL DEFAULT 'a_verifier'
               CHECK (statut IN ('a_verifier','verifie','depose','paye')),
  user_id    INTEGER REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (mission_id, chambre_id)
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS tel TEXT;

ALTER TABLE paiements ADD COLUMN IF NOT EXISTS devise         TEXT NOT NULL DEFAULT 'DA';
ALTER TABLE paiements ADD COLUMN IF NOT EXISTS taux           NUMERIC(10,2);
ALTER TABLE paiements ADD COLUMN IF NOT EXISTS montant_devise NUMERIC(14,2);
ALTER TABLE paiements ADD COLUMN IF NOT EXISTS moyen          TEXT NOT NULL DEFAULT 'cash';

CREATE TABLE IF NOT EXISTS messages (
  id         SERIAL PRIMARY KEY,
  de_user    INTEGER NOT NULL REFERENCES users(id),
  a_user     INTEGER NOT NULL REFERENCES users(id),
  texte      TEXT NOT NULL,
  lu         BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_messages_a    ON messages(a_user, lu);
CREATE INDEX IF NOT EXISTS idx_messages_pair ON messages(de_user, a_user, id);

CREATE INDEX IF NOT EXISTS idx_missions_voyageur ON missions(voyageur_id);
CREATE INDEX IF NOT EXISTS idx_missions_statut   ON missions(statut);
CREATE INDEX IF NOT EXISTS idx_produits_mission  ON produits_mission(mission_id);
CREATE INDEX IF NOT EXISTS idx_paiements_mission ON paiements(mission_id);
CREATE INDEX IF NOT EXISTS idx_tranches_voyageur ON tranches_devises(voyageur_id);

ALTER TABLE users ADD COLUMN IF NOT EXISTS photo      BYTEA;
ALTER TABLE users ADD COLUMN IF NOT EXISTS photo_mime TEXT;

ALTER TABLE missions ADD COLUMN IF NOT EXISTS frais_taxi        NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE missions ADD COLUMN IF NOT EXISTS commission_versee BOOLEAN NOT NULL DEFAULT FALSE;
