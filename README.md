# BuyFood

Native iOS-Einkaufslisten-App (SwiftUI) mit PocketBase-Backend.

## Backend (`backend/`)
- Server: `valiqs@89.58.8.83`, Ordner `/home/buyfood/pb`, Docker-Container `buyfood-pocketbase` (restart: unless-stopped)
- URL: `http://89.58.8.83:8097` (Admin: `/_/`), Admin-Zugang: `/home/buyfood/pb/ADMIN_LOGIN.txt` auf dem Server
- `pb_hooks/` (Apple-Login, Einladungen) und `pb_migrations/` (Collections + Regeln) liegen auf dem Server unter `/home/buyfood/pb/`; Hooks laden automatisch neu, Migrationen laufen beim Containerstart (`docker restart buyfood-pocketbase`).
- Apple-Login: `POST /api/buyfood/apple-auth` prüft das Identity-Token (RS256, Audience = Bundle-ID, Nonce) selbst.
- Bundle-ID muss in `backend/pb_hooks/lib.js` (`BUNDLE_IDS`) und im Xcode-Projekt übereinstimmen.

## App (`ios/`)
- `ios/BuyFood.xcodeproj` in Xcode öffnen, unter Signing & Capabilities das Team wählen, auf echtem iPhone starten.
- HTTP wird nur für 89.58.8.83 per ATS-Ausnahme erlaubt (`ios/Config/Info.plist`) – vor einem Release auf HTTPS umstellen.
