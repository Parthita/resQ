# resQ architecture

resQ is local-first. There is no backend dependency for its primary flows.

```text
Flutter UI
  |
  +-- document intelligence -- PDF text/OCR -- local search -- local LLM
  +-- nearby transport ------ BLE discovery -- Wi-Fi Direct transfer
  +-- secure store ---------- Android Keystore -- encrypted local database
  +-- device sensors -------- GPS -- compass -- barometer -- torch
```

## Document assistant

1. Import a PDF into private local app storage.
2. Extract text locally and OCR pages that have no text layer.
3. Split text into page-aware chunks and store a local FTS index.
4. Select relevant chunks for each question.
5. Send only those chunks and the question to the on-device model.
6. Return the answer with page references and a safety flag.

For small PDFs, the full document may fit in the model context. Large files use
the local section search above; the document never leaves the device. Vault
encryption is a later security milestone and is not yet implemented.

## Nearby messaging

1. BLE advertises a rotating anonymous identifier and discovers peers.
2. The user explicitly selects a peer and verifies a short code or QR invite.
3. Devices exchange public keys and create a trusted contact or group session.
4. Small messages can travel over BLE; large payloads use Wi-Fi Direct when
   both devices support it.
5. Relay packets contain a message ID, expiration, hop limit, encrypted body,
   and signature. Relays cannot read message content.

An active wideband jammer can block all local radios. resQ must present this
honestly: it queues messages and resumes delivery when a usable link returns;
it is not jammer-proof.

## Android integrations to add

- `file_picker` and `pdfx`/platform PDF extraction for document import.
- Bundled ML Kit or Tesseract for offline OCR.
- An on-device runtime such as llama.cpp or LiteRT for language and vision.
- BLE plus a Kotlin platform channel for discovery, advertising, and Wi-Fi
  Direct transfers.
- Drift/SQLite with keys held in Android Keystore.
- Android location, sensor, torch, biometrics, and foreground-service APIs.
