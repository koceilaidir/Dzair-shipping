@echo off
setlocal
cd /d "%~dp0"

echo ================================================
echo   Publication de Dzair Shipping
echo ================================================
echo.

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 goto pasdepot

git status --porcelain > "%TEMP%\dz_status.txt"
for %%A in ("%TEMP%\dz_status.txt") do set TAILLE=%%~zA
del "%TEMP%\dz_status.txt"
if "%TAILLE%"=="0" goto vide

echo Modifications detectees :
git status --short
echo.

set MESSAGE=
set /p MESSAGE=Message de la mise a jour :
if "%MESSAGE%"=="" set MESSAGE=Mise a jour

git add -A
if errorlevel 1 goto echec
git commit -m "%MESSAGE%"
if errorlevel 1 goto echec
goto envoi

:vide
echo Aucune modification a publier.
echo.
set RELANCE=
set /p RELANCE=Relancer quand meme le deploiement ? [o/N] :
if /i not "%RELANCE%"=="o" goto fin
git commit --allow-empty -m "Relance du deploiement"
if errorlevel 1 goto echec

:envoi
echo.
echo Envoi vers GitHub...
git push
if errorlevel 1 goto echec
echo.
echo ================================================
echo   Envoye. GitHub compile et publie sur le VPS.
echo   Suivi des etapes :
echo   https://github.com/koceilaidir/Dzair-shipping/actions
echo   Compter 5 a 8 minutes.
echo ================================================
echo.
pause
exit /b 0

:pasdepot
echo Ce dossier n'est pas un depot Git.
pause
exit /b 1

:echec
echo.
echo Echec. Lis le message ci-dessus.
pause
exit /b 1

:fin
pause
exit /b 0
