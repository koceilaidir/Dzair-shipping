#!/bin/sh
set -e

DEPOT=/root/app
VPS="$DEPOT/deploy/vps"

echo "== Recuperation du code =="
cd "$DEPOT"
git fetch --all --prune
git reset --hard origin/main

echo "== Reconstruction de l'API =="
cd "$VPS"
docker compose up -d --build api

echo "== Publication du site =="
mkdir -p "$VPS/web"
rm -rf "$VPS/web"/*
tar -xzf /tmp/web.tgz -C "$VPS/web"/
rm -f /tmp/web.tgz
test -f "$VPS/web/index.html" || { echo "ECHEC : index.html absent apres extraction."; exit 1; }

echo "== Controle =="
docker compose ps
docker compose logs --tail 25 api
ls "$VPS/web" | head -6
