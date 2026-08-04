# Code signing policy

Free code signing provided by [SignPath.io](https://signpath.io/), certificate by [SignPath Foundation](https://signpath.org/).

## Signed artifacts

Only Windows release artifacts published from the official
[`taeminHan/dejavu`](https://github.com/taeminHan/dejavu) repository are eligible
for Dejavu code signing. Development builds and files shared outside the official
GitHub Releases page are not official signed releases.

Signed releases must:

- be built from a version tag by the repository's GitHub Actions release workflow;
- use GitHub-hosted build runners and retain verifiable source provenance;
- be approved manually in SignPath before signing;
- carry the Dejavu product name and the release version derived from the tag; and
- publish SHA-256 checksums after signing.

## Project roles

- Author and committer: [taeminHan](https://github.com/taeminHan)
- Reviewer: [taeminHan](https://github.com/taeminHan)
- Signing approver: [taeminHan](https://github.com/taeminHan)

Additional maintainers will be listed here before they receive repository or
SignPath access. All maintainers with signing-related access must enable
multi-factor authentication for both GitHub and SignPath.

## Release approval

Every signing request requires a manual approval. The approver checks that the
requested version matches the Git tag, the build comes from the official release
workflow, and the artifact belongs to Dejavu. Signing credentials are not stored
in the repository or distributed to contributors.

## Privacy and uninstall

Dejavu's data handling is documented in the [privacy policy](PRIVACY.md). The app
does not send usage data to a Dejavu server. Users can remove Dejavu from Windows
Installed apps; uninstall removes the app and its own local settings and cache,
but does not remove Claude or Codex account data.

## Verifying a release

After downloading an official release, inspect its Authenticode signature in
PowerShell:

```powershell
Get-AuthenticodeSignature .\dejavu-Setup.exe |
  Format-List Status, StatusMessage, SignerCertificate, TimeStamperCertificate
```

For a signed production release, `Status` must be `Valid`. Also compare the file
against the release's `SHA256SUMS.txt` before running it.
