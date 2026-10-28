@echo off
title DualGuard - WorkBuddy CN
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0dg-launch.ps1" -Product cn
exit /b
