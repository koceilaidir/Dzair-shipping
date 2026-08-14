# API Dzair Shipping — développement local (Docker)

*Docker est notre standard : même environnement en local et sur le VPS.*

## Prérequis (une seule fois)
**Docker Desktop** : https://www.docker.com/products/docker-desktop/ (laisser les réglages par défaut, WSL2 inclus).

## Démarrage

Depuis le dossier `api/` :

```
copy .env.example .env
```

→ ouvre `.env` et remplis : `JWT_SECRET` (longue chaîne aléatoire, 64+ caractères) et ajoute une ligne `DB_PASSWORD=un_mot_de_passe_solide`.

```
docker compose up -d
```

Premier démarrage : la base PostgreSQL est créée avec le schéma complet automatiquement. Ensuite, crée ton compte admin :

```
docker compose exec api npm run create-admin -- koceilaidir92@gmail.com "UnMotDePasseFort!" "Koceila"
```

**Test** : http://localhost:3000/api/health → doit répondre `{"ok":true,"service":"dzair-shipping-api"}`.

## Commandes utiles

```
docker compose up -d          # démarrer (ou redémarrer après un changement de code : ajouter --build)
docker compose logs -f api    # voir les logs de l'API en direct
docker compose down           # tout arrêter (les données restent dans le volume)
docker compose exec db psql -U dzair -d dzair    # ouvrir un terminal SQL dans la base
```

## Notes

- Les données vivent dans le volume Docker `dzair_pgdata` — elles survivent aux arrêts/redémarrages. Sauvegarde : `docker compose exec db pg_dump -U dzair dzair > backup.sql`.
- **Sur le VPS** : même compose, deux changements — supprimer la ligne `ports` du service `db` (la base ne doit jamais être exposée à l'extérieur) et mettre Caddy devant l'API pour le HTTPS.
- Le `.env` ne va jamais sur git (déjà dans `.gitignore`).

## Ce qui est en place

- Auth JWT (`POST /api/auth/login`) avec anti brute-force (10 essais / 15 min)
- Rôles vérifiés côté serveur (`admin` / `voyageur` / `client`)
- Helmet, CORS restreint, rate limiting global, validation zod, requêtes préparées (anti-injection)
- Schéma complet : users, voyageurs, missions (avec champs de vol pour l'avion de suivi), produits, paiements, tranches de devises, remboursements de dette, journal d'audit
- Premier module type : `GET/POST /api/voyageurs` (réservé admin) — le modèle pour la suite
