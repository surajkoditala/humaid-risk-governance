# Local-only corporate CA certs for Docker builds

If `docker build` fails during `dotnet restore` with `NU1301` / "The remote certificate is invalid
because of errors in the certificate chain: UntrustedRoot" (or curl-style "self-signed certificate
in certificate chain"), you're on a network with an SSL-inspecting proxy (Netskope, Zscaler, a
corporate firewall, etc.). Your Windows host already trusts that proxy's root certificate, but the
Linux container `dotnet build` runs in does not — so any outbound HTTPS call inside the build
(NuGet included) fails.

The same interception also breaks the **running app's own** outbound HTTPS calls once it's up -
Auth0's JWKS endpoint (JWT signature validation fails with "the signature key was not found") and
the Anthropic API. Both Dockerfiles trust this folder's certs in the runtime image too, not just the
build stage, for exactly that reason.

**Fix:** export your machine's proxy root CA and drop it here as a `.crt` file (PEM format), directly
in this folder - not a subfolder. `update-ca-certificates` does not recurse into subdirectories, so a
cert placed anywhere but directly here is silently ignored ("0 added", no error). Both Dockerfiles
copy everything in this folder into the image's trust store, in both the build and runtime stages.
This folder is gitignored except for this README and `.gitkeep` — never commit an actual
certificate, and nothing here affects the real deployment pipeline (there's no corporate proxy
between Azure Container Apps and Auth0/NuGet/Anthropic).

## How to export it (Windows, PowerShell)

Find the non-standard root CA (usually named after your proxy vendor):

```powershell
Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -match "Netskope|Zscaler" } | Select-Object Subject, Thumbprint
```

Export it as PEM:

```powershell
$cert = Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -match "Netskope" } | Select-Object -First 1
[System.IO.File]::WriteAllText("ops\certs\my-proxy-root.crt", "-----BEGIN CERTIFICATE-----`n" + [Convert]::ToBase64String($cert.RawData, 'InsertLineBreaks') + "`n-----END CERTIFICATE-----`n")
```

If nothing here matches your setup and the build still fails, check for other SSL-inspecting
software (Sophos, Trellix/McAfee, etc. running local web-filtering) with the same command against a
broader subject match.
