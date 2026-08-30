# Déploiement VPS — dzairshipping.com (Octenium, Ubuntu 24.04, 5.196.162.68)

Architecture : tout tourne sur le VPS en Docker — Postgres (la base chez toi, plus de Supabase), l'API Node, et Caddy qui sert le site Flutter et route `/api` vers l'API, avec HTTPS automatique.

## 1. DNS (Octenium)
Zone DNS de dzairshipping.com — remplacer les anciens enregistrements GitHub Pages :
- A : `@` → 5.196.162.68
- A : `www` → 5.196.162.68

## 2. Sur le VPS (une seule fois)
```bash
ssh ubuntu@5.196.162.68
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
exit
```
(se reconnecter pour que le groupe docker soit actif)

```bash
ssh ubuntu@5.196.162.68
sudo ufw allow 22 && sudo ufw allow 80 && sudo ufw allow 443 && sudo ufw --force enable
git clone https://github.com/koceilaidir/Dzair-shipping.git app
cd app/deploy/vps
cp env.example .env
openssl rand -hex 32   # → coller comme JWT_SECRET dans .env
nano .env              # DB_PASSWORD (lettres+chiffres) et JWT_SECRET
mkdir -p web
docker compose up -d --build
docker compose logs api | tail -5   # attendre « ✓ Schéma de base vérifié/appliqué »
```

## 3. Le site Flutter (depuis le PC, à chaque mise à jour du front)
Double-cliquer `deployer-web.bat` à la racine du projet (build release avec la bonne API_URL puis envoi par scp), ou à la main :
```bat
flutter build web --release --dart-define=API_URL=https://dzairshipping.com/api
scp -r build\web\* ubuntu@5.196.162.68:~/app/deploy/vps/web/
```

## 4. Premier compte admin
```bash
docker compose exec db psql -U dzair -d dzair -c "create extension if not exists pgcrypto; insert into users (email, password_hash, role, nom) values ('koceilaidir92@gmail.com', crypt('TON_MOT_DE_PASSE', gen_salt('bf', 10)), 'admin', 'Koceila');"
```
Puis effacer la commande de l'historique : `history -c`.

## 5. Vérifier
- https://dzairshipping.com → page de connexion (le premier chargement peut prendre ~1 min le temps que Caddy obtienne le certificat)
- https://dzairshipping.com/api/health → {"ok":true}

## Mises à jour au quotidien
- **API** (après un git push) : `ssh ubuntu@5.196.162.68` puis `cd app && git pull && cd deploy/vps && docker compose up -d --build api`
- **Site** : `deployer-web.bat` depuis le PC
- Le schéma SQL s'applique tout seul au redémarrage de l'API (idempotent)

## Sauvegarde de la base (recommandé, hebdo)
```bash
docker compose exec db pg_dump -U dzair dzair > sauvegarde-$(date +%F).sql
```
Rapatrier sur le PC : `scp ubuntu@5.196.162.68:~/app/deploy/vps/sauvegarde-*.sql .`

## Notes
- CORS déjà réglé sur le domaine ; API et site sur la même origine.
- Render/Supabase/GitHub Pages peuvent être conservés quelque temps comme secours puis résiliés.
- Si l'utilisateur SSH d'Octenium est `root`, remplacer `ubuntu@` par `root@` partout (et pas besoin de sudo).
