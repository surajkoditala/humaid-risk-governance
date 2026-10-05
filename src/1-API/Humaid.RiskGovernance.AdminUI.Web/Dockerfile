# Build context is the repo ROOT (not this folder) - this project references sibling projects
# by relative path (../../2-Infrastructure, ../../3-Service/..., ../../4-Persistence/...), so the
# build stage needs all of them. From the repo root:
#   docker build -f src/1-API/Humaid.RiskGovernance.AdminUI.Web/Dockerfile -t humaid-workbench .
#
# Config is unchanged from local dev - every value is read via IConfiguration flat keys
# (screaming-snake-case), so it maps directly onto `docker run -e KEY=value` / Container App env
# vars. See ops/README.md for the full variable table. This image does not bake in any secret.

# Bake the frontend into this image's own wwwroot, same pattern as the ERC admin UI project: Vite
# turns webapp/ into plain static files, the throwaway node stage below never ships in the final
# image, and at runtime the single .NET process both serves /api/... and hands back the built
# index.html/assets for everything else (Program.cs's UseDefaultFiles/UseStaticFiles). Without
# this stage wwwroot is empty and every non-API route 404s - that's what shipped before this fix.
FROM node:22-alpine AS webapp-build
WORKDIR /webapp

# Epic 11: Vite inlines import.meta.env.VITE_* into the bundle at THIS build step, not at container
# start - unlike every backend config value in this repo (flat IConfiguration keys read at runtime),
# these three cannot be set as a Container App env var later and take effect. They must reach
# `docker build` as --build-args (see .azure-pipelines/workbench/environments/dev.yml and
# templates/variables.yml). Defaulting to empty keeps every build that doesn't pass them identical
# to before this change - isAuth0Configured (authConfig.js) is false, same "acting as" dev mode.
ARG VITE_AUTH0_DOMAIN=""
ARG VITE_AUTH0_CLIENT_ID=""
ARG VITE_AUTH0_AUDIENCE=""

COPY webapp/package.json webapp/package-lock.json ./
RUN npm ci
COPY webapp/ ./
# Empty string, not unset - api.js's apiFetch defaults to http://localhost:5210 when this is
# unset (its ?? fallback), which would bake the wrong base URL into the production bundle since
# Vite inlines import.meta.env.VITE_* at build time. Empty string means same-origin, which is
# correct once the built assets are served from this same container.
ENV VITE_API_BASE_URL=""
ENV VITE_AUTH0_DOMAIN=${VITE_AUTH0_DOMAIN}
ENV VITE_AUTH0_CLIENT_ID=${VITE_AUTH0_CLIENT_ID}
ENV VITE_AUTH0_AUDIENCE=${VITE_AUTH0_AUDIENCE}
RUN npm run build

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Optional: trust an extra local root CA before any network call (NuGet restore included) - needed
# when building behind an SSL-inspecting corporate proxy (Netskope, Zscaler, etc.) whose root cert
# the Windows host trusts but this Linux build stage does not. Only ops/certs/.gitkeep is tracked
# in git; drop your own *.crt there locally (gitignored) if `dotnet restore` fails with NU1301/
# UntrustedRoot. No-op (and no build-time cost) when the directory holds no real certs - see
# ops/certs/README.md. Must land directly in ca-certificates/ - update-ca-certificates does NOT
# recurse into subdirectories (confirmed against this same base image; a nested extra/ subfolder
# is silently ignored, "0 added" every time with no error).
COPY ops/certs/ /usr/local/share/ca-certificates/
RUN find /usr/local/share/ca-certificates/ -maxdepth 1 \( -name '*.crt' -o -name '*.pem' \) | grep -q . && update-ca-certificates || true

# Copy csproj files first so `dotnet restore` is cached separately from source changes.
COPY src/1-API/Humaid.RiskGovernance.AdminUI.Web/*.csproj src/1-API/Humaid.RiskGovernance.AdminUI.Web/
COPY src/2-Infrastructure/Humaid.RiskGovernance.AdminUI.Infrastructure/*.csproj src/2-Infrastructure/Humaid.RiskGovernance.AdminUI.Infrastructure/
COPY src/3-Service/Humaid.RiskGovernance.AdminUI.Services/*.csproj src/3-Service/Humaid.RiskGovernance.AdminUI.Services/
COPY src/3-Service/Humaid.RiskGovernance.AdminUI.AI/*.csproj src/3-Service/Humaid.RiskGovernance.AdminUI.AI/
COPY src/4-Persistence/Humaid.RiskGovernance.AdminUI.DA/*.csproj src/4-Persistence/Humaid.RiskGovernance.AdminUI.DA/
RUN dotnet restore src/1-API/Humaid.RiskGovernance.AdminUI.Web/Humaid.RiskGovernance.AdminUI.Web.csproj

# Now the rest of the source and publish. webapp/ (5-Presentation) has no ProjectReference here -
# it's built separately by the webapp-build stage above and copied straight into wwwroot below.
COPY src/1-API/Humaid.RiskGovernance.AdminUI.Web/ src/1-API/Humaid.RiskGovernance.AdminUI.Web/
COPY src/2-Infrastructure/Humaid.RiskGovernance.AdminUI.Infrastructure/ src/2-Infrastructure/Humaid.RiskGovernance.AdminUI.Infrastructure/
COPY src/3-Service/Humaid.RiskGovernance.AdminUI.Services/ src/3-Service/Humaid.RiskGovernance.AdminUI.Services/
COPY src/3-Service/Humaid.RiskGovernance.AdminUI.AI/ src/3-Service/Humaid.RiskGovernance.AdminUI.AI/
COPY src/4-Persistence/Humaid.RiskGovernance.AdminUI.DA/ src/4-Persistence/Humaid.RiskGovernance.AdminUI.DA/
# DEF-007: this plain-SQL folder (schema/functions/migrations/seed, no .csproj) was never copied
# into either service's image, so DbMigrationRunner had nothing to apply on a fresh deploy and
# every request 500'd. Copied into the runtime stage below at ./db - see Program.cs's
# ResolveDbFolderPath.
COPY src/4-Persistence/Humaid.RiskGovernance.AdminUI.DB/ src/4-Persistence/Humaid.RiskGovernance.AdminUI.DB/

RUN dotnet publish src/1-API/Humaid.RiskGovernance.AdminUI.Web/Humaid.RiskGovernance.AdminUI.Web.csproj \
    -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
# The base image's OS packages can lag behind their own upstream security fixes (e.g.
# CVE-2026-84782 in openssl/libssl3t64) even on an unpinned "latest for this tag" pull - the
# Trivy HIGH/CRITICAL gate in the deploy pipeline catches this. Patch at build time rather than
# pinning a digest, which would just go stale again the next time a CVE lands.
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*
WORKDIR /app

# Same corporate-proxy trust as the build stage above (see ops/certs/README.md) - but this one
# matters at RUNTIME, not just at build. The app's own outbound HTTPS calls (Auth0's JWKS endpoint
# for JWT signature validation, the Anthropic API) go through the same SSL-inspecting proxy as
# `dotnet restore` did, and this stage starts from a fresh base image that never saw the build
# stage's trust store update. Without this, JWT validation fails with "the signature key was not
# found" (the app can't fetch Auth0's real signing keys) even though login itself works fine (the
# browser, running on the host, already trusts the proxy's root cert).
USER root
COPY ops/certs/ /usr/local/share/ca-certificates/
RUN find /usr/local/share/ca-certificates/ -maxdepth 1 \( -name '*.crt' -o -name '*.pem' \) | grep -q . && update-ca-certificates || true

COPY --from=build /app/publish .
COPY --from=webapp-build /webapp/dist ./wwwroot
COPY --from=build /src/src/4-Persistence/Humaid.RiskGovernance.AdminUI.DB ./db

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

# Run as the non-root `app` user that the .NET 8+ aspnet images ship (APP_UID is set by the
# base image). Port 8080 is > 1024, so no privileges are needed to bind it.
USER $APP_UID

ENTRYPOINT ["dotnet", "Humaid.RiskGovernance.AdminUI.Web.dll"]
