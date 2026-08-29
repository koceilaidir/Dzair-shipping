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

-- v4 — devise du compte BEA, allocation touristique, solde de devises reporté, vol & visa.
ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS devise_compte       TEXT NOT NULL DEFAULT 'USD';
ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS allocation_eligible BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS allocation_derniere DATE;
ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS solde_devises       NUMERIC(14,2) NOT NULL DEFAULT 0;
ALTER TABLE missions  ADD COLUMN IF NOT EXISTS frais_visa          NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE missions  ADD COLUMN IF NOT EXISTS allocation_utilisee BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE missions  ADD COLUMN IF NOT EXISTS factures_total      NUMERIC(14,2);
ALTER TABLE missions  ADD COLUMN IF NOT EXISTS heure_depart        TEXT;
ALTER TABLE missions  ADD COLUMN IF NOT EXISTS heure_arrivee       TEXT;

-- v5 — statut voyageur, argent de poche, demandes de suppression.
ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS statut_dispo TEXT NOT NULL DEFAULT 'disponible'
  CHECK (statut_dispo IN ('disponible','indisponible','limite'));
ALTER TABLE missions ADD COLUMN IF NOT EXISTS poche_mode TEXT NOT NULL DEFAULT 'cash_da'
  CHECK (poche_mode IN ('cash_da','rmb_alipay','cash_devise','carte'));
ALTER TABLE missions ADD COLUMN IF NOT EXISTS poche_frais_carte NUMERIC(12,2) NOT NULL DEFAULT 0;

-- Demandes de suppression d'une mission clôturée (validées par tous les admins).
CREATE TABLE IF NOT EXISTS demandes_suppression (
  id          SERIAL PRIMARY KEY,
  mission_id  INTEGER NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
  demandeur   INTEGER NOT NULL REFERENCES users(id),
  approbateurs JSONB NOT NULL DEFAULT '[]', -- ids ayant approuvé
  statut      TEXT NOT NULL DEFAULT 'en_attente' CHECK (statut IN ('en_attente','approuvee','rejetee')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- v6 — l'argent de poche devient des tranches (motif 'poche').
ALTER TABLE tranches_devises DROP CONSTRAINT IF EXISTS tranches_devises_motif_check;
ALTER TABLE tranches_devises ADD CONSTRAINT tranches_devises_motif_check
  CHECK (motif IN ('voyage','depot_bloque','poche'));

-- v7 — valise déclarée complète (même non pleine) : verrouille l'ajout et ouvre le check retour.
ALTER TABLE missions ADD COLUMN IF NOT EXISTS valise_close BOOLEAN NOT NULL DEFAULT FALSE;

-- v8 — Chambres (grossistes en Chine + leur dépôt en Algérie), bons de récupération,
-- inventaire (lignes en stock) et affectations produit → valise d'une mission.
CREATE TABLE IF NOT EXISTS chambres (
  id            SERIAL PRIMARY KEY,
  nom           TEXT NOT NULL,                        -- nom ou numéro de la chambre
  ville         TEXT NOT NULL DEFAULT 'Canton',
  depot_adresse TEXT,                                 -- adresse du dépôt en Algérie
  depot_wilaya  TEXT,
  note          TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS chambre_contacts (
  id         SERIAL PRIMARY KEY,
  chambre_id INTEGER NOT NULL REFERENCES chambres(id) ON DELETE CASCADE,
  nom        TEXT NOT NULL,
  tel        TEXT,
  role       TEXT                                     -- dépôt / chambre / patron…
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
  quantite    NUMERIC(10,2) NOT NULL,                 -- pièces récupérées
  poids_total NUMERIC(10,3) NOT NULL,                 -- kg pour toute la quantité
  manque_rmb  NUMERIC(12,2) NOT NULL DEFAULT 0,       -- remboursé par pièce perdue (RMB)
  mode        TEXT NOT NULL DEFAULT 'kg' CHECK (mode IN ('kg','piece')),
  prix        NUMERIC(12,2) NOT NULL DEFAULT 0        -- DA/kg ou DA/pièce payé par le dépôt
);
CREATE TABLE IF NOT EXISTS affectations (
  id         SERIAL PRIMARY KEY,
  ligne_id   INTEGER NOT NULL REFERENCES bon_lignes(id) ON DELETE CASCADE,
  mission_id INTEGER NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
  quantite   NUMERIC(10,2) NOT NULL,
  manquants  NUMERIC(10,2) NOT NULL DEFAULT 0,        -- pièces perdues, déclarées à la clôture
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE missions ADD COLUMN IF NOT EXISTS manques_da NUMERIC(14,2) NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_affect_mission ON affectations(mission_id);
CREATE INDEX IF NOT EXISTS idx_affect_ligne   ON affectations(ligne_id);
CREATE INDEX IF NOT EXISTS idx_bons_chambre   ON bons(chambre_id);

-- v9 — société(s) de facturation (factures des valises), prix déclaré par pièce.
CREATE TABLE IF NOT EXISTS societes_facturation (
  id          SERIAL PRIMARY KEY,
  nom_cn      TEXT NOT NULL,
  nom_en      TEXT NOT NULL DEFAULT '',
  code_credit TEXT NOT NULL DEFAULT '',            -- 统一社会信用代码
  adresse_cn  TEXT NOT NULL DEFAULT '',
  adresse_en  TEXT NOT NULL DEFAULT '',
  tel         TEXT NOT NULL DEFAULT '',
  email       TEXT NOT NULL DEFAULT '',
  devise      TEXT NOT NULL DEFAULT 'USD',
  par_defaut  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Société initiale (depuis la licence 营业执照) — modifiable dans Réglages.
INSERT INTO societes_facturation (nom_cn, nom_en, code_credit, adresse_cn, adresse_en, par_defaut)
SELECT '广州觅涅伍贸易有限公司', 'GUANGZHOU MINIEWU TRADING CO., LTD.', '91440106MAK9J26C7Q',
       '广州市天河区天河北路179号12层自编04房562号',
       'Room 562, Self-numbered 04, 12/F, No.179 Tianhe North Road, Tianhe District, Guangzhou', TRUE
WHERE NOT EXISTS (SELECT 1 FROM societes_facturation);
-- Prix déclaré (USD / pièce) : sur l'affectation (ce qui part dans la valise) et
-- mémorisé sur la ligne du bon (dernier prix connu, pré-rempli la fois suivante).
ALTER TABLE affectations ADD COLUMN IF NOT EXISTS prix_declare NUMERIC(12,2);
ALTER TABLE bon_lignes   ADD COLUMN IF NOT EXISTS prix_declare NUMERIC(12,2);
-- Identité client sur les factures : nom latin (comme sur le passeport) + adresse en Algérie.
ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS nom_passeport TEXT;   -- ex. BENALI YACINE
ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS adresse       TEXT;   -- adresse en latin, Algérie
ALTER TABLE voyageurs ADD COLUMN IF NOT EXISTS wilaya        TEXT;

-- v10 — factures des valises (émises par la société de facturation, figées à la génération).
CREATE TABLE IF NOT EXISTS factures (
  id             SERIAL PRIMARY KEY,
  mission_id     INTEGER NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
  societe_id     INTEGER REFERENCES societes_facturation(id),
  numero         INTEGER NOT NULL,                        -- aléatoire 0-30 (demande Koceila)
  date           DATE NOT NULL,
  client_nom     TEXT NOT NULL DEFAULT '',
  client_tel     TEXT NOT NULL DEFAULT '',
  client_adresse TEXT NOT NULL DEFAULT '',
  devise         TEXT NOT NULL DEFAULT 'USD',
  taux_rmb       NUMERIC(10,4) NOT NULL DEFAULT 0,        -- RMB pour 1 USD
  total          NUMERIC(14,2) NOT NULL DEFAULT 0,        -- USD
  total_rmb      NUMERIC(14,2) NOT NULL DEFAULT 0,
  lignes         JSONB NOT NULL DEFAULT '[]',             -- [{produit, quantite, prix, montant, affectation_id}]
  societe        JSONB NOT NULL DEFAULT '{}',             -- copie figée de l'en-tête société
  statut         TEXT NOT NULL DEFAULT 'emise' CHECK (statut IN ('emise','annulee')),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_factures_mission ON factures(mission_id);

-- v11 — retours de marchandise aux chambres (fin de séjour) : l'inventaire doit être
-- vide avant le dernier retour ; chaque restitution est enregistrée, l'historique reste.
CREATE TABLE IF NOT EXISTS retours (
  id         SERIAL PRIMARY KEY,
  ligne_id   INTEGER NOT NULL REFERENCES bon_lignes(id) ON DELETE CASCADE,
  quantite   NUMERIC(10,2) NOT NULL,
  date       DATE NOT NULL DEFAULT CURRENT_DATE,
  user_id    INTEGER REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_retours_ligne ON retours(ligne_id);

-- v12 — taxes d'arrivée séparées : douane 5 % + IFU 0,5 %. La douane ajoute PARFOIS
-- une marge de 30 % au CA avant l'IFU : le choix appliqué se fige sur la mission à
-- la clôture (NULL = suivre le réglage ifu_marge_30 tant que la mission est ouverte).
ALTER TABLE missions ADD COLUMN IF NOT EXISTS ifu_marge BOOLEAN;

-- v13 — bagages supplémentaires & douane à l'arrivée.
-- 3e valise achetée à la compagnie (prix = dépense de mission, poids ajouté à la
-- capacité, produits déclarés/facturés normalement) ; bagage à main 8 kg : produits
-- NON déclarés (jamais facturés, jamais dans la base douane/IFU, rien via la carte
-- BEA) mais comptés dans le revenu, le prix du kilo, les bons de remise et la
-- traçabilité. À l'arrivée : taxes réellement payées (remplacent la prévision) +
-- photo du bon des douaniers + saisie éventuelle (traitée comme les manques :
-- hors revenu et remboursée à la chambre au prix du manque).
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
  type       TEXT NOT NULL,                            -- 'bon_douane'
  mime       TEXT NOT NULL DEFAULT 'image/jpeg',
  data       BYTEA NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_mission_docs ON mission_docs(mission_id);

-- v14 — retour & créances : restes d'argent tracés (motif 'reste' : ce que le
-- voyageur REND à l'agence — cash devise/DA, RMB Alipay… — réduit la dépense
-- poche réelle), encaissements PAR DÉPÔT (paiements.chambre_id) et statut de
-- remise par dépôt (à vérifier → vérifié → déposé → payé).
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

-- v15 — numéro de téléphone de l'admin : affiché sur les bons (récupération et
-- remise) pour que chambres et dépôts puissent le joindre. Réglable dans
-- Réglages → Mon profil.
ALTER TABLE users ADD COLUMN IF NOT EXISTS tel TEXT;

CREATE INDEX IF NOT EXISTS idx_missions_voyageur ON missions(voyageur_id);
CREATE INDEX IF NOT EXISTS idx_missions_statut   ON missions(statut);
CREATE INDEX IF NOT EXISTS idx_produits_mission  ON produits_mission(mission_id);
CREATE INDEX IF NOT EXISTS idx_paiements_mission ON paiements(mission_id);
CREATE INDEX IF NOT EXISTS idx_tranches_voyageur ON tranches_devises(voyageur_id);
