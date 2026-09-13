@echo off
cd /d "%~dp0"
call "C:\Users\Lenovo\OneDrive\Bureau\flutter\bin\flutter.bat" build web --release --dart-define=API_URL=https://dzairshipping.com/api
if errorlevel 1 (
  echo Echec du build Flutter.
  pause
  exit /b 1
)

echo.
echo Envoi du site en une archive compressee...
tar -czf web.tgz -C build\web .
if errorlevel 1 (
  echo Echec de la compression.
  pause
  exit /b 1
)

scp -C -o IPQoS=throughput web.tgz root@5.196.162.68:/tmp/web.tgz
if errorlevel 1 (
  echo Echec de l'envoi - verifie la connexion SSH.
  del web.tgz
  pause
  exit /b 1
)

ssh -o IPQoS=throughput root@5.196.162.68 "rm -rf ~/app/deploy/vps/web/* && tar -xzf /tmp/web.tgz -C ~/app/deploy/vps/web/ && rm /tmp/web.tgz && ls ~/app/deploy/vps/web/ | head -5"
if errorlevel 1 (
  echo Echec du deploiement sur le serveur.
  del web.tgz
  pause
  exit /b 1
)

del web.tgz
echo.
echo Site publie sur https://dzairshipping.com
pause
