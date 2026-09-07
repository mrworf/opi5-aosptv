# Configure the pre-authorized ADB public key

Every build requires `config/adb/adbkey.pub`.  The file is intentionally
ignored by Git but is read from this repository, not directly from your home
directory.

Import an existing Android ADB public key:

```bash
./configure-adb-key --from "$HOME/.android/adbkey.pub"
```

If no key exists, create a pair and then import only its public half:

```bash
adb keygen "$HOME/.android/adbkey"
./configure-adb-key --from "$HOME/.android/adbkey.pub"
```

Never copy `~/.android/adbkey` into this repository.  The configuration command
rejects private-key material, validates the Android public-key encoding,
confirms the destination is ignored, and prints a SHA-256 fingerprint.
