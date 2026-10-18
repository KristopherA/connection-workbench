# Connection Workbench

[Download builds](https://github.com/KristopherA/connection-workbench/releases) · [Signing and notarization](SIGNING.md) · [Deployment](DEPLOYMENT.md)

A native macOS app for help-desk and sysadmin connection troubleshooting. Capture the same service under two conditions, compare observations, and hand off a support bundle with the evidence attached.

## Run

Open **Connection Workbench.app**. You do not need Homebrew, Python, Xcode, an agent, or administrator privileges to run it. The companion `connection-workbench` command is optional.

The app is built as a universal executable for Apple Silicon and Intel, with a macOS 13 deployment target. This release was exercised on the current Apple Silicon workstation; the Intel command-line executable was also exercised through Rosetta. Older macOS versions and physical Intel hardware still require deployment acceptance testing.

This local build uses an ad-hoc signature. It is **not Developer ID signed or notarized**. For organization-wide delivery, use your normal signing, notarization, and managed distribution process. Do not disable Gatekeeper or remove quarantine attributes as a deployment method. See `DEPLOYMENT.md`.

## Five-minute procedure

1. Enter the exact service URL. A hostname defaults to HTTPS. Use the intended port and path. Do not include credentials, query strings, or fragments.
2. Describe condition A, for example “Office network / VPN connected / affected Mac.” Confirm the condition manually and reproduce the user's symptom in the affected application. Click **Capture A** and wait for completion.
3. Change one condition through the organization's normal procedure: VPN state, network, or workstation. Wait until it is stable. The app does not change network settings.
4. Describe condition B and click **Capture B**. For another workstation, save its capture and use **Import…** in the appropriate slot. Both captures must use the same target.
5. Review **Findings**, inspect both sides under **Evidence**, and follow the suggested next tests. Use **Export support bundle** for escalation. Review the content before sharing it.

Capture A does not have to be the working condition. Label what you actually observed. Do not label a condition as working solely because a probe got an HTTP response.

Captures remain in memory until saved or exported. Closing the app or choosing **New comparison** discards the current in-memory comparison. **Retake** clears that slot so its condition can be changed and collected again. Save useful captures first.

## What is collected

| Evidence | Collection | Interpretation |
|---|---|---|
| DNS configuration | `scutil --dns` | Scoped and supplemental resolvers, including configuration relevant to split DNS |
| Proxy configuration | `scutil --proxy` | Configured proxies, exceptions, and PAC settings; the app does not independently execute or inspect PAC scripts |
| Network context | `scutil --nwi`, before and after probes | Available network state; a change during capture is flagged |
| VPN service list | `scutil --nc list` | Listed service state only; third-party VPNs may be absent |
| Resolver answers | `dscacheutil -q host -a name …` | Host-query observation; it is not evidence of every application's DNS behavior |
| Destination routes | `route -n get …` | Routes for up to eight unique addresses observed in the resolver query, including IPv6 |
| macOS application request | Ephemeral `URLSession`, HEAD | Uses macOS application networking and default trust evaluation; has no cookie jar or credential store |
| Certificate fingerprints | SHA-256 over observed trust-challenge chain | Collected when the application probe observes a server-trust challenge; absence is not a trust pass |
| Direct request | Apple-provided curl, HEAD | Explicitly ignores curl configuration, environment proxies, and configured HTTP proxies; VPNs and transparent filters still apply |
| Probe metrics | curl exit, HTTP code, peer/local IP, port, timing, verification result | Stage evidence rather than a synthetic health score |

Both requests have time limits, do not follow redirects, do not save response bodies or headers, do not load browser sessions, and leave certificate verification enabled. Configuration commands have timeouts and output limits. No shell interprets target strings. No public resolver, third-party enrichment service, or telemetry endpoint is contacted by the app. Requests to your chosen service may involve its configured DNS, proxy, and operating-system certificate services.

An individual capture can take over a minute when multiple collection steps time out. The progress indicator shows the active step. There is no mid-capture cancellation button in this version; quitting terminates the app, and each child command also has a bounded lifetime.

## Reading results

- **HTTP 200/204:** a response was received. This does not verify login, JavaScript, browser state, or application health.
- **HTTP 301/302:** the original service responded with a redirect. The destination was not tested automatically.
- **HTTP 401/403:** a reachable server may require authentication or enforce access policy. The probe sends no stored credentials.
- **HTTP 405:** HEAD may be unsupported. Do not treat this alone as a connection fault.
- **Direct failure with an application response:** investigate proxy/PAC policy and trust differences. Direct access may intentionally be blocked.
- **Different DNS, peer, or certificate:** split DNS, load balancing, renewal, and expected inspection are possible explanations. Verify before assigning a cause.
- **No tracked differences:** these observations did not isolate the symptom. Browser-specific behavior, intermittent faults, credentials, or untested layers may still explain it.
- **Unavailable evidence:** inspect the command error or timeout. Missing evidence is never counted as a passing check.

Captures are sequential snapshots. They do not measure all paths at the same instant, establish causation, capture packets, inspect application content, or prove the absence of compromise. `URLSession` is not a substitute for the exact affected browser. Timing comparisons are single samples, not statistical performance measurements.

## Escalation bundle

The ZIP contains `capture-A.json`, optionally `capture-B.json`, `report.md`, and `SHA256SUMS.txt`. JSON includes timestamps, macOS version, condition label, target, application probe observations, and command evidence with exit status and duration. The report includes findings and next tests. A saved JSON can be imported into another copy of the app without running probes.

Bundles are **not redacted or encrypted**. They can include internal hostnames, IP addresses, proxy/PAC URLs, VPN service names, target paths, operator labels, and other configuration identifiers. The app does not deliberately collect the workstation name, username, serial number, stored credentials, or browser history. Review all attachments and use approved ticket or file-transfer systems. There is no automatic upload.

Hashes help detect changes after export; they are not an authenticity signature or forensic chain of custody. Imported captures are external observations, not independently verified facts. Imports are bounded to 5 MB and validate the schema and target. The source schema is defined in `Sources/Core.swift`.

## Scripted collection

```sh
./connection-workbench capture https://service.example.com \
  --label "VPN connected / affected Mac" \
  --output ./capture-A.json
```

The CLI refuses to overwrite an existing output file. Import its JSON into the app to compare or export. The CLI returns zero when a capture was saved, even if connection probes failed; probe failures are observations inside the JSON. A nonzero CLI exit means argument, validation, or file-save failure. There is no scheduler or background daemon.

## Build and test

Development requires Apple's Command Line Tools with Swift and a macOS SDK. Runtime users do not need them. No third-party Swift packages are used.

```sh
./build.sh ./dist
./test.sh
./test.sh --integration
```

The integration suite additionally needs Python 3 and Apple's OpenSSL executable for a temporary self-signed TLS fixture. It uses loopback-only dynamically allocated ports, makes no production service requests, and removes fixture private keys afterward. It checks HEAD responses, redirects remaining unfollowed, dropped connections, and rejection of an untrusted certificate. The core suite checks target validation, comparison behavior, process timeout, import validation, export contents, and payload hashes.

## Source layout

- `Sources/Core.swift`: data model, bounded process runner, probes, comparisons, import/export.
- `Sources/App.swift`: guided native SwiftUI app and evidence view.
- `Sources/CLI.swift`: noninteractive capture tool.
- `Tests/`: core and loopback integration checks.
- `Tools/Icon.swift`: original app icon renderer.
- `build.sh`: universal build, app bundle assembly, and local signing.

This version is a practical diagnostic tool. Planned extensions should preserve the distinction between observations, hypotheses, and verified causes; add collectors through explicit bounded operations rather than arbitrary imported commands.
