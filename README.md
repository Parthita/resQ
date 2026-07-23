# resQ

resQ is an offline-first safety and coordination app for any situation where
internet access is unavailable or untrusted. Its first vertical slice combines:

- Local document chat and summaries.
- Nearby people, trusted contacts, and encrypted group communication.
- SOS, location sharing, and a general sensor dashboard.
- A local library for guides, documents, notes, and captured observations.

## Current implementation

PDF import and native-text indexing are implemented. resQ copies user-selected
PDFs into private app storage, extracts their selectable text page by page,
stores local search sections, and returns page-cited excerpts in Assistant.
Scanned PDFs that contain no selectable text are marked for OCR. OCR, local
model answers, and encrypted vault storage are the next integrations.

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
