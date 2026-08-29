# Déploiement — phase test (gratuit)

Architecture : **GitHub Pages** (front Flutter, ton domaine) + **Supabase** (Postgres managé) + **Render** (API Node en conteneur). Rien à réécrire : l'API et le schéma tournent tels quels.

```
navigateur ──> GitHub Pages (Flutter web, domaine)
                   │  HTTPS
                   ▼
              Render (API Express :3000, conteneur api/Dockerfile)
                   │  TLS
                   ▼
              Supabase (PostgreSQL — schéma auto-appliqué au démarrage)
```

## 1. Pousser le code (une fois)
Dans le dossier `dzair_shipping` (PowerShell) :
```
git init                      # (inutile si déjà fait)
git remote add origin https://github.com/koceilaidir/Dzair-shipping.git
git add .
git commit -m "Dzair Shipping — app + API + déploiement"
git branch -M main
git push -u origin main
```
⚠ Vérifie AVANT le premier push que `api/.env` n'apparaît pas dans `git status` (le `.gitignore` l'exclut). Si le dépôt doit rester privé : Settings → General → visibilité. GitHub Pages sur dépôt privé demande un compte Pro — sinon passe le dépôt en public (le `.env` n'y est jamais).

## 2. Supabase (la base)
1. supabase.com → New project (région EU de préférence) → choisis un mot de passe base solide.
2. Project Settings → Database → **Connection string → Session pooler** (port 5432, host `…pooler.supabase.com`) — c'est CELLE-LÀ (Render est en IPv4, la connexion directe est IPv6).
3. Note l'URL complète `postgresql://postgres.xxxx:MOTDEPASSE@…pooler.supabase.com:5432/postgres`.
> Le schéma (v15) s'applique tout seul au premier démarrage de l'API. Gratuit : le projet se met en pause après ~1 semaine sans requête — il se relance depuis le dashboard.

## 3. Render (l'API)
1. render.com → New → **Blueprint** → connecte le dépôt `Dzair-shipping` — Render lit `render.yaml`.
2. Renseigne quand il les demande :
   - `DATABASE_URL` : l'URL Supabase de l'étape 2 ;
   - `JWT_SECRET` : 64+ caractères aléatoires (garde-le quelque part).
3. Déploie. L'URL sera du genre `https://dzair-shipping-api.onrender.com` — teste `…/api/health`.
> Gratuit : l'API s'endort après 15 min d'inactivité (~1 min de réveil au premier appel).
> Crée le premier compte admin comme en local (script/seed habituel) — la base Supabase démarre vide.

## 4. GitHub Pages (le front)
1. Dépôt → Settings → Pages → Source : **GitHub Actions**.
2. Si l'URL Render diffère de `dzair-shipping-api.onrender.com`, corrige `API_URL` en tête de `.github/workflows/deploy-web.yml`.
3. Pousse sur `main` → l'action build et publie. Site : `https://koceilaidir.github.io/Dzair-shipping/`.

## 5. Le domaine
1. Mets ton domaine dans `DOMAIN:` en tête du workflow (et ajoute `,https://TONDOMAINE` à `CORS_ORIGIN` sur Render).
2. Chez ton registrar :
   - `www` → CNAME → `koceilaidir.github.io`
   - racine (`@`) → 4 enregistrements A → `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`
3. Dépôt → Settings → Pages → Custom domain → ton domaine → coche **Enforce HTTPS** (le certificat prend quelques minutes).

## À savoir
- **Chine** : github.io/Pages passe mal depuis la Chine — OK pour tester depuis l'Algérie ; pour l'usage réel en voyage, bascule prévue sur un VPS (docker compose identique, nginx + domaine + HTTPS).
- Les photos des bons de douane vivent dans Postgres (Supabase) — rien d'autre à configurer.
- Chaque `git push` sur `main` republie le front automatiquement. L'API se redéploie aussi à chaque push (Render suit le dépôt).
