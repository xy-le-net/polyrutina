flutter clean
flutter pub get
flutter build apk --release 2>&1 | Tee-Object -FilePath buildlog_apk.txt
flutter build windows --release 2>&1 | Tee-Object -FilePath buildlog_win.txt
