flutter build apk --release 2>&1 | Tee-Object -FilePath apk_build_log_short.txt
copy "D:\polyrutina\build\app\outputs\flutter-apk\app-release.apk" "C:\Users\Администратор\Desktop\"
flutter build windows --release 2>&1 | Tee-Object -FilePath win_build_log_short.txt
