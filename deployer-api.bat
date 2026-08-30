@echo off
ssh root@5.196.162.68 "cd app && git pull && cd deploy/vps && docker compose up -d --build api && docker compose logs api --tail 3"
if errorlevel 1 (
  echo Echec — verifie la connexion SSH et que le git push est fait.
  pause
  exit /b 1
)
echo API mise a jour sur https://dzairshipping.com
pause
