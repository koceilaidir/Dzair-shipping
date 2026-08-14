-- Dzair Shipping — schéma PostgreSQL v0.1
-- Exécuter :  psql -U postgres -d dzair -f db/schema.sql

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
  user_id         INTEGER REFERENCES users(id),          -- compte de connexion (créé par l'admin)
  nom             TEXT NOT NULL,
  tel             TEXT,
  comm_mode       TEXT NOT NULL DEFAULT 'kg' CHECK (comm_mode IN ('kg','pct','fixe')),
  comm_val        NUMERIC(12,2) NOT NULL DEFAULT 0,      -- DA/kg, % ou montant fixe selon comm_mode
  bagages         INTEGER NOT NULL DEFAULT 2,
  depuis          TEXT,
  dette_active    BOOLEAN NOT NULL DEFAULT FALSE,        -- 1 100 $ avancés par l'agence ?
  dette_montant   NUMERIC(14,2) NOT NULL DEFAULT 0,      -- en DA (somme des tranches d'achat)
  dette_rembourse NUMERIC(14,2) NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS missions (
  id              SERIAL PRIMARY KEY,
  voyageur_id     INTEGER NOT NULL REFERENCES voyageurs(id),
  code            TEXT NOT NULL UNIQUE,                  -- MSN-001…
  vol             TEXT,
  depart          DATE,
  retour          DATE,
  heure_decollage TIMESTAMPTZ,                           -- pour l'avion de suivi (progression sans GPS)
  duree_vol_min   INTEGER,                               -- durée de vol en minutes
  jours           INTEGER NOT NULL DEFAULT 5,
  budget_jour     NUMERIC(12,2) NOT NULL DEFAULT 3000,   -- per-diem : dépense/jour à ne pas dépasser
  billet          NUMERIC(12,2) NOT NULL DEFAULT 0,
  dem_type        TEXT NOT NULL DEFAULT 'multiple'
                    CHECK (dem_type IN ('premiere','renouvellement','visa_double','multiple')),
  dem_cout        NUMERIC(12,2) NOT NULL DEFAULT 0,
  bea             NUMERIC(12,2) NOT NULL DEFAULT 0,      -- frais de transaction carte BEA
  douane          NUMERIC(12,2) NOT NULL DEFAULT 0,      -- payée à l'arrivée
  autres          NUMERIC(12,2) NOT NULL DEFAULT 0,
  objectif        NUMERIC(12,2) NOT NULL DEFAULT 20000,  -- bénéfice minimum visé
  kg_soute        NUMERIC(6,2)  NOT NULL DEFAULT 46,
  cabine          BOOLEAN NOT NULL DEFAULT FALSE,        -- +10 kg, dernier recours
  val_declaree    NUMERIC(14,2),                         -- ≤ 1 800 000 DA (contrôle applicatif + alerte)
  statut          TEXT NOT NULL DEFAULT 'planifiee'
                    CHECK (statut IN ('planifiee','encours','cloturee','annulee')),
  depot           TEXT,
  attendu         NUMERIC(14,2),                         -- montant attendu à la revente (après invendus)
  primes          NUMERIC(12,2) NOT NULL DEFAULT 0,      -- économies per-diem reversées
  invendus        TEXT,
  cloture_date    DATE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS produits_mission (
  id         SERIAL PRIMARY KEY,
  mission_id INTEGER NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
  nom        TEXT NOT NULL,
  kg         NUMERIC(8,2)  NOT NULL,
  prix_kg    NUMERIC(12,2) NOT NULL                       -- rendement DA/kg
);

CREATE TABLE IF NOT EXISTS paiements (
  id         SERIAL PRIMARY KEY,
  mission_id INTEGER NOT NULL REFERENCES missions(id),
  date       DATE NOT NULL DEFAULT CURRENT_DATE,
  montant    NUMERIC(14,2) NOT NULL,
  note       TEXT
);

-- Devises chargées en tranches (objectif ~2 000 $/voyage) ou pour bloquer le dépôt 1 100 $.
CREATE TABLE IF NOT EXISTS tranches_devises (
  id          SERIAL PRIMARY KEY,
  voyageur_id INTEGER NOT NULL REFERENCES voyageurs(id),
  mission_id  INTEGER REFERENCES missions(id),
  usd         NUMERIC(12,2) NOT NULL,
  taux        NUMERIC(8,2)  NOT NULL,                     -- DA/USD au moment de l'achat
  date        DATE NOT NULL DEFAULT CURRENT_DATE,
  source      TEXT,
  motif       TEXT NOT NULL DEFAULT 'voyage' CHECK (motif IN ('voyage','depot_bloque'))
);

CREATE TABLE IF NOT EXISTS remboursements_dette (
  id          SERIAL PRIMARY KEY,
  voyageur_id INTEGER NOT NULL REFERENCES voyageurs(id),
  date        DATE NOT NULL DEFAULT CURRENT_DATE,
  montant     NUMERIC(14,2) NOT NULL,                     -- toujours stocké en DA
  devise      TEXT NOT NULL DEFAULT 'DA' CHECK (devise IN ('DA','USD')),
  taux        NUMERIC(8,2)                                -- si remboursé en USD : taux appliqué
);

-- Qui a fait quoi, quand — exigé par le cahier des charges (invendus, corrections…).
CREATE TABLE IF NOT EXISTS audit_log (
  id         SERIAL PRIMARY KEY,
  user_id    INTEGER REFERENCES users(id),
  action     TEXT NOT NULL,
  entite     TEXT NOT NULL,
  entite_id  INTEGER,
  details    JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- v2 — commission figée par mission (la compta passée ne bouge jamais) + historique.
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

-- v3 — validités voyageur, checklists mission, devises multi-monnaies, réglages globaux.
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

CREATE INDEX IF NOT EXISTS idx_missions_voyageur ON missions(voyageur_id);
CREATE INDEX IF NOT EXISTS idx_missions_statut   ON missions(statut);
CREATE INDEX IF NOT EXISTS idx_produits_mission  ON produits_mission(mission_id);
CREATE INDEX IF NOT EXISTS idx_paiements_mission ON paiements(mission_id);
CREATE INDEX IF NOT EXISTS idx_tranches_voyageur ON tranches_devises(voyageur_id);
