flutter clean
flutter pub get
flutter build apk --release 2>&1 | Tee-Object -FilePath apk_build_log_short.txt
flutter build windows --release 2>&1 | Tee-Object -FilePath win_build_log_short.txt
