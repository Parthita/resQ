# resQ

resQ is an offline-first safety and coordination app for any situation where
internet access is unavailable or untrusted. Its first vertical slice combines:

- Local document chat and summaries.
- Nearby people, trusted contacts, and encrypted group communication.
- SOS, location sharing, and a general sensor dashboard.
- A local library for guides, documents, notes, and captured observations.

## Current implementation

PDF import is implemented. resQ copies user-selected PDFs into private app
storage, persists their local metadata, shows them in Library, and makes them
selectable as Assistant context. PDF text extraction, OCR, local model answers,
and encrypted vault storage are the next integrations.

## Run locally

Once Flutter's Android command-line tools and licenses are configured, run the
app:

```bash
flutter pub get
flutter run -d linux
```

For nearby-device testing, use two physical Android phones. The resQ UI is ready for
the native services; BLE/Wi-Fi Direct, local inference, OCR, and encrypted
storage are intentionally represented by service boundaries in the next pass.
