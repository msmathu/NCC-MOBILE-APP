@echo off
rem Double-click to host NCC Cadet Challenge for players anywhere (free Cloudflare tunnel).
title NCC Cadet Challenge - public server
cd /d "%~dp0server"
if not exist node_modules call npm install --omit=dev
node scripts\go-public.mjs
pause
