@echo off
chcp 65001 >nul
title 报告快车道
cd /d "%~dp0"
echo ============================================
echo   报告快车道：跳过 48 个月，几秒出报告
echo ============================================
echo.
python backend\api\gen_report.py --slot demo --html
if errorlevel 1 (
  echo.
  echo [失败] 报告生成失败，请把上面的报错发给开发。
  pause
  exit /b 1
)
echo.
echo 正在打开报告预览页...
start "" "%~dp0report_out\report_preview.html"
echo [完成] 报告 JSON 在 report_out\report.json
timeout /t 2 >nul
