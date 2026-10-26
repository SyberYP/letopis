# Letopis security

**English** · [Русский](SECURITY.ru.md)

## What is protected, and from whom

| Threat | Protection |
|---|---|
| Someone gets the app's files (a backup, root, a stolen phone without the password) | Everything is encrypted with AES-256-GCM. The data key (DEK) is wrapped with a key derived from the password (Argon2id, 19 MiB, 2 passes). Without the password the files are useless |
| Encrypted files swapped or moved around | The file path (`entries/<id>`, `media/<id>`…) is part of every chunk's AAD: a file moved under another name will not decrypt |
| A foreign or corrupted sync repository | Only paths like `vault.json`, `entries/<id>.md.enc`, `media|thumbs/<id>.enc` are taken. A `vault.json` from the repository is accepted only if the current key opens it |
| An imported file with traps in an id or attachment name (`../`) | Ids are checked (`[A-Za-z0-9_-]{1,64}`), extensions too (`[a-z0-9]{1,10}`); imported entries get a new id and no foreign attachments |
| A `vault.json` with huge Argon2id parameters (hang, out of memory) | Parameters are capped: memory ≤ 2 GiB, passes ≤ 64, threads ≤ 16 |
| Plaintext leaking into a public repository | The "open Markdown" mode checks that the repository is private and sends nothing otherwise |
| Entry text leaking over the network | Network access is limited to GitHub (the user's token) and the chosen AI service (HTTPS only, after consent; consent resets when the address changes). Links from entries open only after confirmation |
| A forged update | Every build is signed with an upload key kept outside the repository. The old personal key with a public password was retired by signature rotation (v3) without rollback rights: an APK signed with it will not install over version 1.1.1+ |
| Shoulder surfing | Auto-lock when the app goes to the background; optional screenshot blocking (`FLAG_SECURE`) |

Plaintext reaches the disk only in the temporary folder for video/audio playback and when sharing
(a temporary file); the folder is wiped on lock.

## Known limitations

- **Biometrics.** With fingerprint unlock on, the data key is kept in `flutter_secure_storage`
  (encrypted with an Android Keystore key), and the app itself asks for the fingerprint. The Keystore key
  is not bound to biometric confirmation: with full access to the process (root, a debugger) the key can
  be obtained without a fingerprint. Without biometrics this risk does not exist. The fix is
  `AndroidOptions.biometric(enforceBiometrics: true, requireBiometricsPerOperation: true)`; it needs
  testing on a device.
- **Metadata.** The number, size and modification time of files are visible to anyone with access to
  the files or to the sync repository. Tags and text are not.
- **A forgotten password** cannot be recovered (by design).
- **The GitHub token** is stored in the encrypted settings. Use a fine-grained token for one repository
  with *Contents: Read and write*.

## Reporting a vulnerability

Email <sybberr@gmail.com>. Please do not publish details until a fix is released.
