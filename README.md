# freefire-xeno-panel

Internal panel for Free Fire iOS. Non-jailbroken, no substrate, no Mac required.

## Pipeline

1. Get a **decrypted** Free Fire IPA (App Store IPAs are FairPlay-encrypted and won't load an injected dylib).
2. `Actions → build → Run workflow`, paste the IPA URL.
3. Download the `xeno` artifact.
4. Sign + install on device with ESign or Feather using your cert.
5. Launch, log in with Garena ID.

## Verify the offsets before you trust them

Every constant in `src/Offsets.h` is build-specific. Grab the UUID from the
UnityFramework slice of *your* IPA and put it in `kExpectedUUID`:

    dwarfdump --uuid Payload/FreeFire.app/Frameworks/UnityFramework.framework/UnityFramework

If the panel header reads `uuid mismatch`, the module loaded but the offsets
belong to a different build — nothing below the header is reliable. Update
`kDumpDate` when you re-dump.

## On-device debugging

No console, so the panel writes a breadcrumb ring to
`Documents/xeno_crash.log` on SIGSEGV/SIGBUS/SIGABRT. Read it through the
Files app after a crash — the last line names the stage that died.

## Known limits

- Free Fire updates often; offsets rot within weeks. The UUID gate makes that
  a visible failure instead of a silent one.
- Position hacks are client-side. Fly/noclip get corrected by the server on
  movement replication; expect rubber-banding.
- `Attr_UnlimitedAmmo` is the least verified offset here. If ammo still drains,
  it's an int on the weapon instance, not a bool on the attributes object.
- Re-signing changes the team identifier, so Facebook and Google login can fail.
  Garena ID email login is the reliable path.
- Modded clients are detectable. Assume bans in ranked are possible.
- `AimRotation` is written as world-space player rotation. If the game fights
  you, the aim field is camera-local and `Cam_ViewMatrixField` needs re-probing.
