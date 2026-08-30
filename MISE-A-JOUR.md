# Mettre à jour dzairshipping.com (VPS)

Le site vit sur le VPS (5.196.162.68). Une mise à jour se fait toujours en deux temps : envoyer le code sur GitHub, puis dire au serveur de le récupérer.

## Étape 1 — toujours : pousser le code sur GitHub
Dans le terminal, à la racine du projet :
```
git add -A
git commit -m "description courte du changement"
git push
```

## Étape 2 — selon ce qui a changé

### A. L'API a changé (fichiers dans `api\`)
Double-cliquer **`deployer-api.bat`** à la racine du projet (il demande le mot de passe SSH), ou à la main :
```
ssh root@5.196.162.68 "cd app && git pull && cd deploy/vps && docker compose up -d --build api"
```
Le schéma de la base s'applique tout seul au redémarrage (aucune commande SQL à faire, jamais).

### B. Le site a changé (fichiers dans `lib\`)
Double-cliquer **`deployer-web.bat`** à la racine du projet. Il compile et envoie le site. Ensuite Ctrl+F5 dans le navigateur.

### C. Les deux ont changé
`deployer-api.bat` puis `deployer-web.bat`. L'ordre API d'abord, site ensuite.

## Vérifier que tout va bien
- https://dzairshipping.com/api/health → {"ok":true}
- https://dzairshipping.com → Ctrl+F5, se connecter, tester ce qui a changé

## Si quelque chose ne va pas
Voir les erreurs de l'API :
```
ssh root@5.196.162.68 "cd app/deploy/vps && docker compose logs api --tail 30"
```
Revenir à la version précédente du code :
```
ssh root@5.196.162.68 "cd app && git log --oneline -5"
ssh root@5.196.162.68 "cd app && git checkout LE_CODE_DU_COMMIT && cd deploy/vps && docker compose up -d --build api"
```
(puis `git checkout main` pour revenir à la normale une fois le problème corrigé)

## Sauvegarde de la base (à faire régulièrement)
```
ssh root@5.196.162.68 "cd app/deploy/vps && docker compose exec db pg_dump -U dzair dzair" > sauvegarde.sql
```
Cette commande, lancée depuis le PC, enregistre `sauvegarde.sql` dans le dossier courant — à garder précieusement.
