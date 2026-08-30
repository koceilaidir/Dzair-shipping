@echo off
cd /d "%~dp0"
call flutter build web --release --dart-define=API_URL=https://dzairshipping.com/api
if errorlevel 1 (
  echo Echec du build Flutter.
  pause
  exit /b 1
)
scp -r build\web\* ubuntu@5.196.162.68:~/app/deploy/vps/web/
if errorlevel 1 (
  echo Echec de l'envoi — verifie la connexion SSH.
  pause
  exit /b 1
)
echo Site publie sur https://dzairshipping.com
pause
