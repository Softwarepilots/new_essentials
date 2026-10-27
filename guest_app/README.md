# EH Guest

Standalone visitor check-in app for Essential Homes (Android + iOS).
Separate from the staff app in `../otp_phone_auth`.

- Android application ID / iOS bundle ID: `com.essentialhomes.guest`
- Backend: `POST /api/notifications/guest-checkin/` (no login). The backend
  stores the visit in `guest_checkins` and pushes a notification to admin
  devices; admins see visitors in the staff app's admin dashboard.
- Backend URL: `lib/services/guest_api.dart`

## Run / build

```
flutter pub get
flutter run
flutter build apk --release          # Android
flutter build ios --release          # iOS (on macOS, needs signing)
```
