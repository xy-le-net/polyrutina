@echo off
setlocal

echo Cleaning...
flutter clean
if %errorlevel% neq 0 exit /b %errorlevel%

echo Building APK...
powershell -NoProfile -Command "flutter build apk --release 2>&1 | Tee-Object -FilePath apk_build_log_short.txt"
if %errorlevel% neq 0 exit /b %errorlevel%

copy "D:\polyrutina\build\app\outputs\flutter-apk\app-release.apk" "C:\Users\Администратор\Desktop\"
if %errorlevel% neq 0 exit /b %errorlevel%

echo Building Windows...
powershell -NoProfile -Command "flutter build windows --release 2>&1 | Tee-Object -FilePath win_build_log_short.txt"
if %errorlevel% neq 0 exit /b %errorlevel%

copy "D:\polyrutina\build\windows\x64\runner\Release\polyrutina.exe" "C:\Users\Администратор\Desktop\"
if %errorlevel% neq 0 exit /b %errorlevel%

endlocal
echo Done.
