@echo off
chcp 65001 > nul
title Demo Live He Thong CSDL Omnistock
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0demo_live.ps1"
pause
