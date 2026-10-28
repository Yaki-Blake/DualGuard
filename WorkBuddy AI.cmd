@echo off
title DualGuard - WorkBuddy AI
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0dg-launch.ps1" -Product ai
exit /b
