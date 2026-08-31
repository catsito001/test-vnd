@echo off
cd /d C:\laragon\www\pos

echo.
echo ===== REVISANDO CAMBIOS =====
git status

echo.
echo ===== GUARDANDO CAMBIOS =====
git add .
git commit -m "Actualizacion desde Claude"

echo.
echo ===== SUBIENDO A GITHUB =====
git push origin main

echo.
echo ===== TERMINADO =====
pause