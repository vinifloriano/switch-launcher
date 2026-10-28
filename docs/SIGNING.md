# Signing and notarization

Downloaded apps that aren't signed with a **Developer ID** and **notarized** by Apple trigger
macOS's "unidentified developer" warning (see the README's install steps). Removing it requires a
paid [Apple Developer Program](https://developer.apple.com/programs/) membership; an ad-hoc or
self-signed certificate does not help.

The build already supports it. Until the steps below are done, builds stay ad-hoc signed.

## 1. Certificate (once)

1. Enrol in the Apple Developer Program.
2. Xcode › Settings › Accounts › your team › **Manage Certificates…** › **+** ›
   **Developer ID Application**. The certificate and its private key go into your login keychain.
3. Check it: `security find-identity -v -p codesigning` lists
   `Developer ID Application: Your Name (TEAMID)`.

## 2. Notary login (once)

Create an app-specific password at [account.apple.com](https://account.apple.com) (Sign-In and
Security › App-Specific Passwords), then store it in the keychain under a profile name:

```bash
xcrun notarytool store-credentials switch-launcher --apple-id you@example.com --team-id TEAMID
```

## 3. Build signed and notarized

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=switch-launcher \
    ./scripts/build-app.sh --dist
```

This signs with the hardened runtime and a secure timestamp, uploads the zip to Apple's notary
service, staples the ticket to the app, re-zips it and checks it with `spctl`.

## CI

- **Gitea** (the runner is this Mac): set repository variables `SIGN_IDENTITY` and
  `NOTARY_PROFILE` (Settings › Actions › Variables). The runner uses the login keychain.
- **GitHub**: add repository secrets `MACOS_CERT_P12` (the certificate exported as .p12, base64:
  `base64 -i cert.p12 | pbcopy`), `MACOS_CERT_PASSWORD`, `SIGN_IDENTITY`, `APPLE_ID`,
  `APPLE_TEAM_ID` and `APPLE_APP_PASSWORD`. The workflow imports them into a temporary keychain.
