# Deployment and help-desk acceptance

## Release status

The delivered app and CLI contain arm64 and x86_64 slices, target macOS 13 or later, and use only operating-system frameworks and command-line tools. The release is ad-hoc signed for local testing, not notarized. A universal binary and deployment target are not a substitute for testing your supported hardware and OS versions.

## Organization distribution

Follow [your organization's app and package signing procedure](SIGNING.md). It covers certificate identification, Developer ID Application signing, Developer ID Installer package signing, notarization, stapling, and pilot verification. It also provides a separate installer path for the optional command-line collector.

Your organization’s package signing certificate alone does not sign the application. Confirm the exact certificate type and availability of an Application signing identity before beginning. The procedure uses a release copy and preserves the original build.

## Acceptance checklist

On each supported macOS release and CPU architecture:

- Launch as a standard user from the real delivery channel; confirm Gatekeeper acceptance.
- Test a known service on office Wi-Fi, the approved VPN, and another approved network. Confirm labels match the real network conditions.
- Exercise a proxy/PAC environment, including required proxy authentication. The probe intentionally does not supply stored credentials; document expected challenges and failures.
- Verify IPv4 and IPv6 destinations, a split-DNS hostname, an invalid hostname, an unreachable service, an expired or untrusted certificate, a redirect, and a HEAD-rejecting service.
- Compare the application's output against the actual browser symptom. Record differences caused by browser DNS, trust, authentication, extensions, or per-application VPN policy.
- Test importing a capture from another workstation using the identical service URL, plus rejection of an inconsistent target and unsupported schema.
- Save and export under a standard user account. Extract the ZIP and verify its manifest hashes. Confirm the report has enough context for the next support tier.
- Review the bundle against your data-handling policy. Set a retention location, access restrictions, and approved sharing destination.
- Confirm VoiceOver labels, keyboard navigation, appearance, and window sizing with the help-desk team.

## Ticket handoff template

Service URL:

User-visible symptom and exact reproduction time/time zone:

Affected application and version:

Condition A / observed user result:

Condition B / observed user result:

What changed between captures:

Key observed differences and evidence IDs:

Next test or team needed:

Bundle reviewed and attached using the approved channel:

Do not put passwords, session tokens, or personal information in condition labels. If a reproduction requires a secret-bearing URL, ask the service owner for a safe diagnostic endpoint; this tool deliberately rejects query strings and embedded credentials.
