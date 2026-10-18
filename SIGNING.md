# Sign and distribute Connection Workbench

**Owner:** your organization's macOS packaging / Apple Developer account administrators  
**Updated:** 18 October 2026  
**Application:** Connection Workbench 1.0.0, macOS 13+, Apple Silicon and Intel  
**Deliverable:** A signed, notarized installer that installs the app in `/Applications`.

Your organization’s package signing certificate can sign the installer **if it is a Developer ID Installer certificate**. Signing the app itself requires a separate **Developer ID Application** certificate. An installer signature does not replace an app signature. [Apple's certificate types](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).

This procedure has been prepared for organizational distribution; your organization's certificate names, Team ID, private-key availability, and notarization access have not been inspected or assumed. No organizational signing or Apple submission has been performed. The certificate-dependent steps must be completed on your organization's signing Mac. Each application uses its own bundle and installer identifiers. No organization-specific certificate identity is embedded in the application.

## 1. Confirm the signing identities

Use your organization's designated signing Mac and approved keychain. In **Keychain Access → My Certificates**, locate the package signing certificate and expand it. A usable signing identity contains both its certificate and corresponding private key; importing a `.cer` alone is insufficient.

List valid identities in Terminal:

```sh
security find-identity -v
security find-identity -v -p codesigning
```

Use the first command to find installer identities. The `codesigning` filter in the second command is useful for application identities but filters out installer identities. [Apple's packaging guidance](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).

| your organization's certificate name begins with | Use in this procedure |
|---|---|
| `Developer ID Installer:` | Sign the `.pkg` installer |
| `Developer ID Application:` | Sign the `.app` and optional command-line executable |
| `3rd Party Mac Developer Installer:` or a Mac App Store distribution identity | Different distribution channel; obtain the Developer ID identities for this procedure |
| An internal CA / organization-issued package signing name | May support your organization's managed package trust arrangement, but does not substitute for Developer ID app signing or Apple's notarization requirements |

**If your organization has only Developer ID Installer:** ask your organization’s Apple Developer Account Holder, or administrator with the applicable certificate permissions, to arrange a Developer ID Application signing identity for the same team. Use your organization's approved certificate provisioning method; keep private keys in the approved keychain or signing service. Do not send private keys, `.p12` passwords, or notarization secrets through a support ticket.

## 2. Prepare the tools and release copy

Use an approved, current Xcode installation with `codesign`, `productbuild`, `pkgutil`, `notarytool`, and `stapler` available. Check:

```sh
xcode-select -p
xcrun --find notarytool
xcrun --find stapler
```

If the tools are missing, install or select your organization's approved Xcode version through the normal workstation process. Internet access to Apple's timestamp and notarization services is required.

Extract `ConnectionWorkbench.zip`. In Terminal, change to the extracted **ConnectionWorkbench** folder containing the app, CLI, and documentation. Keep the same Terminal session for the following commands.

Set these variables, replacing both identity placeholders with the **exact names** from step 1:

```sh
WORKBENCH_SOURCE="$PWD"
WORKBENCH_VERSION='1.0.0'
WORKBENCH_APP_IDENTITY='Developer ID Application: REPLACE WITH EXACT ORGANIZATION NAME (TEAMID)'
WORKBENCH_INSTALLER_IDENTITY='Developer ID Installer: REPLACE WITH EXACT ORGANIZATION NAME (TEAMID)'
WORKBENCH_NOTARY_PROFILE='Organization-ConnectionWorkbench-Notary'
WORKBENCH_RELEASE="$(mktemp -d /private/tmp/Organization-ConnectionWorkbench.XXXXXX)"
WORKBENCH_APP="$WORKBENCH_RELEASE/Connection Workbench.app"
WORKBENCH_PKG="$WORKBENCH_RELEASE/ConnectionWorkbench-$WORKBENCH_VERSION.pkg"

ditto --norsrc \
  "$WORKBENCH_SOURCE/Connection Workbench.app" \
  "$WORKBENCH_APP"

/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  "$WORKBENCH_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$WORKBENCH_APP/Contents/Info.plist"
lipo -archs "$WORKBENCH_APP/Contents/MacOS/ConnectionWorkbench"
```

Expected: bundle ID `tools.connectionworkbench.desktop`, version `1.0.0`, and architectures `arm64` and `x86_64` in either order. Stop if the version or artifact is not the intended release. The working copy is outside cloud-synced folders to avoid Finder/file-provider metadata affecting signing.

For future versions, update the app version and build number in the source before building, and match `WORKBENCH_VERSION` to that release. The included `build.sh` (under `Source/` in a downloadable package) produces an ad-hoc build; **rebuilding after the next step replaces your organization’s signature**, so finish builds before signing.

## 3. Sign the app

```sh
codesign --force --options runtime --timestamp \
  --sign "$WORKBENCH_APP_IDENTITY" \
  "$WORKBENCH_APP"

codesign --verify --strict --verbose=2 "$WORKBENCH_APP"
codesign --display --verbose=4 "$WORKBENCH_APP"
```

Complete any normal keychain private-key authorization on the signing Mac. Confirm the displayed signing authority is your organization's Developer ID Application identity, the Team Identifier matches your organization's team, the flags include `runtime`, and a secure timestamp is present. The verification command must succeed.

This app contains one main executable and no embedded helper executables or third-party frameworks. No additional runtime-exception entitlements are required by this build. Do not add broad exceptions or `--deep` signing to resolve an unexplained signing error. If future releases add nested executable components, sign those components from the inside out before signing the enclosing app. [Apple's notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## 4. Build and sign the installer

The primary package contains the GUI app only; source files, diagnostics, and the optional CLI are excluded. Create requirements so Installer recognizes both architectures and requires macOS 13 or later:

```sh
cat > "$WORKBENCH_RELEASE/requirements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>os</key><array><string>13.0</string></array>
  <key>arch</key><array><string>arm64</string><string>x86_64</string></array>
</dict></plist>
PLIST

productbuild \
  --product "$WORKBENCH_RELEASE/requirements.plist" \
  --component "$WORKBENCH_APP" /Applications \
  --identifier tools.connectionworkbench.desktop.installer \
  --version "$WORKBENCH_VERSION" \
  --sign "$WORKBENCH_INSTALLER_IDENTITY" \
  --timestamp \
  "$WORKBENCH_PKG"

pkgutil --check-signature "$WORKBENCH_PKG"
```

Confirm the package signature is trusted, identifies your organization's Developer ID Installer certificate, and includes the expected certificate chain. Package-signing failures must be resolved before submission. Do not use an Application certificate with `productbuild` or an Installer certificate with `codesign`.

## 5. Configure notarization access once

Use an existing Organization-approved notarytool keychain profile if one is already available; set `WORKBENCH_NOTARY_PROFILE` to its exact name and skip profile creation.

Otherwise, the authorized your organization Apple Developer account operator can create a profile interactively:

```sh
xcrun notarytool store-credentials "$WORKBENCH_NOTARY_PROFILE"
```

For Apple ID authentication, supply the authorized Apple ID, your organization’s Team ID, and an app-specific password when prompted. Your organization may instead use its approved App Store Connect API-key workflow. Credential setup is a release-administrator task, not a help-desk or end-user task. Avoid putting passwords in command arguments or documents. See the installed tool's `store-credentials --help` for supported authentication options.

## 6. Notarize and staple the final package

This step uploads the signed application inside its installer to **Apple's notarization service**. The package should contain release code only; it must not contain workstation captures, credentials, or support bundles.

```sh
xcrun notarytool submit "$WORKBENCH_PKG" \
  --keychain-profile "$WORKBENCH_NOTARY_PROFILE" \
  --wait \
  --output-format json > "$WORKBENCH_RELEASE/notary-result.json"

cat "$WORKBENCH_RELEASE/notary-result.json"
```

Proceed only when the returned status is **Accepted**. An upload ID or successful upload alone is not acceptance. If rejected or if processing is still underway, retain the submission ID and inspect the result:

```sh
xcrun notarytool info 'REPLACE-WITH-SUBMISSION-ID' \
  --keychain-profile "$WORKBENCH_NOTARY_PROFILE"
xcrun notarytool log 'REPLACE-WITH-SUBMISSION-ID' \
  --keychain-profile "$WORKBENCH_NOTARY_PROFILE" \
  "$WORKBENCH_RELEASE/notary-log.json"
```

After acceptance:

```sh
xcrun stapler staple "$WORKBENCH_PKG"
xcrun stapler validate "$WORKBENCH_PKG"
pkgutil --check-signature "$WORKBENCH_PKG"
spctl --assess --type install --verbose=2 "$WORKBENCH_PKG"

shasum -a 256 "$WORKBENCH_PKG" \
  > "$WORKBENCH_RELEASE/ConnectionWorkbench-$WORKBENCH_VERSION.pkg.sha256"
```

All checks must succeed. The package assessment should be accepted and identify notarized Developer ID distribution. Calculate the release hash **after** stapling, because stapling changes the final package bytes. Preserve the notarization result and submission ID with the release record. [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

This procedure notarizes the outer `.pkg`. Do not separately notarize the app first for this package-only delivery. Do not distribute the loose working `.app` as if it were the finished, stapled installer. If your organization also wants a drag-and-drop ZIP release, create and verify that as a separate app distribution workflow.

## 7. Pilot and publish

1. Copy the completed `.pkg`, checksum, and release record from the temporary working directory to your organization's approved release repository before cleaning that directory or restarting the Mac.
2. Deliver the exact package through the intended user-download or MDM channel to a pilot Mac without signing keys. Close any running copy of Connection Workbench before installation. For upgrade testing, retain the previous approved installer.
3. Install through the normal Installer or MDM process. Installation into `/Applications` may require administrator authorization or MDM's installation privileges; running the installed app does not require admin rights.
4. Verify the installed app:

   ```sh
   codesign --verify --strict --verbose=2 "/Applications/Connection Workbench.app"
   codesign --display --verbose=4 "/Applications/Connection Workbench.app"
   spctl --assess --type execute --verbose=2 "/Applications/Connection Workbench.app"
   ```

5. Launch **the copy in `/Applications`** as a standard user. Capture an approved service under two controlled conditions, compare evidence, save/import captures and export a support bundle. Confirm unavailable evidence is not treated as success. Test your organization's actual application-management and profile environment and the oldest macOS release and hardware architectures your organization will support. Confirm installation lands in `/Applications`, including upgrade cases where an older copy has been moved.
6. Release only the pilot-tested, stapled package. A package signature does not replace these functional checks. Use the acceptance checklist in `DEPLOYMENT.md` for the wider rollout.

## Optional: package the command-line companion

Skip this section if your organization needs only the GUI. To deliver the CLI, sign it with the **Application** identity, then place it in its own signed installer. This avoids adding a shell command to every GUI-only workstation.

```sh
WORKBENCH_CLI_STAGE="$WORKBENCH_RELEASE/cli-payload"
WORKBENCH_CLI_PKG="$WORKBENCH_RELEASE/ConnectionWorkbench-CLI-$WORKBENCH_VERSION.pkg"
mkdir -p "$WORKBENCH_CLI_STAGE"
ditto --norsrc "$WORKBENCH_SOURCE/connection-workbench" \
  "$WORKBENCH_CLI_STAGE/connection-workbench"
chmod 755 "$WORKBENCH_CLI_STAGE/connection-workbench"

codesign --force --options runtime --timestamp \
  --sign "$WORKBENCH_APP_IDENTITY" \
  "$WORKBENCH_CLI_STAGE/connection-workbench"
codesign --verify --strict --verbose=2 \
  "$WORKBENCH_CLI_STAGE/connection-workbench"

pkgbuild --root "$WORKBENCH_CLI_STAGE" \
  --install-location /usr/local/bin \
  --ownership recommended \
  --identifier tools.connectionworkbench.cli.installer \
  --version "$WORKBENCH_VERSION" \
  --sign "$WORKBENCH_INSTALLER_IDENTITY" \
  --timestamp \
  "$WORKBENCH_CLI_PKG"
```

Repeat step 6 for **this CLI package**, substituting `WORKBENCH_CLI_PKG` for `WORKBENCH_PKG`, and use distinct notarization-log and checksum filenames. A standalone executable cannot have a stapled ticket attached; staple its notarized installer package instead. Verify the installed `/usr/local/bin/connection-workbench` signature and run `connection-workbench --help` and a capture of an approved diagnostic service during the pilot. See README.md for the CLI arguments.

## Troubleshooting and recovery

| Symptom | Resolution |
|---|---|
| No usable identity / missing private key | Have the signing administrator provision the complete identity through your organization's approved process. A certificate without its private key cannot sign. |
| Certificate exists but signing tool cannot find it | Check certificate type, keychain search list, unlocked keychain, certificate validity, private-key access, and the exact identity name. Installer identities are excluded by `-p codesigning`. |
| `resource fork, Finder information, or similar detritus not allowed` | Recreate the release working copy from the original build with `ditto --norsrc` in the local temporary directory, then sign again. Do not modify an already finalized package. |
| Timestamp or notarization connection fails | Resolve access to Apple's services or credential permissions. Retain the failure log; do not remove timestamping or treat an incomplete submission as accepted. |
| Notarization rejects the artifact | Read the submission log, correct the indicated component, rebuild/re-sign, create a new package, and submit again. |
| Package passes but app assessment or launch fails | Check the installed app's Application signature and Team ID, notarization log, exact installed path, delivery method, and any your organization endpoint policy. Escalate to the packaging or Apple Developer account administrator with logs and submission ID. |
| Pilot functional failure | Pause rollout. Preserve the failed package and test record; correct and issue a new version. If rollback is needed, use your organization's existing MDM rollback/removal process and previous approved installer. Do not assume a lower-version installer will overwrite a newer app. Saved troubleshooting captures are separate user files and should be retained according to policy. |

Do not disable Gatekeeper, remove quarantine as a deployment workaround, or change keychain trust globally to make these checks pass. No certificate export, keychain modification, installation, signing, or Apple upload is performed merely by reading this procedure.
