# Build context is the repo ROOT (not this folder) - this project references sibling projects
# by relative path (../../2-Infrastructure, ../../3-Service/..., ../../4-Persistence/...), so the
# build stage needs all of them. From the repo root:
#   docker build -f src/1-API/Humaid.RiskGovernance.AdminUI.Web/Dockerfile -t humaid-workbench .
#
# Config is unchanged from local dev - every value is read via IConfiguration flat keys
# (screaming-snake-case), so it maps directly onto `docker run -e KEY=value` / Container App env
# vars. See ops/README.md for the full variable table. This image does not bake in any secret.

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Optional: trust an extra local root CA before any network call (NuGet restore included) - needed
# when building behind an SSL-inspecting corporate proxy (Netskope, Zscaler, etc.) whose root cert
# the Windows host trusts but this Linux build stage does not. Only ops/certs/.gitkeep is tracked
# in git; drop your own *.crt there locally (gitignored) if `dotnet restore` fails with NU1301/
# UntrustedRoot. No-op (and no build-time cost) when the directory holds no real certs - see
# ops/certs/README.md.
COPY ops/certs/ /usr/local/share/ca-certificates/extra/
RUN find /usr/local/share/ca-certificates/extra/ -name '*.crt' -o -name '*.pem' | grep -q . && update-ca-certificates || true

# Copy csproj files first so `dotnet restore` is cached separately from source changes.
COPY src/1-API/Humaid.RiskGovernance.AdminUI.Web/*.csproj src/1-API/Humaid.RiskGovernance.AdminUI.Web/
COPY src/2-Infrastructure/Humaid.RiskGovernance.AdminUI.Infrastructure/*.csproj src/2-Infrastructure/Humaid.RiskGovernance.AdminUI.Infrastructure/
COPY src/3-Service/Humaid.RiskGovernance.AdminUI.Services/*.csproj src/3-Service/Humaid.RiskGovernance.AdminUI.Services/
COPY src/3-Service/Humaid.RiskGovernance.AdminUI.AI/*.csproj src/3-Service/Humaid.RiskGovernance.AdminUI.AI/
COPY src/4-Persistence/Humaid.RiskGovernance.AdminUI.DA/*.csproj src/4-Persistence/Humaid.RiskGovernance.AdminUI.DA/
RUN dotnet restore src/1-API/Humaid.RiskGovernance.AdminUI.Web/Humaid.RiskGovernance.AdminUI.Web.csproj

# Now the rest of the source and publish. webapp/ (5-Presentation) is NOT copied - this project has
# no ProjectReference to webapp.esproj, so building it here would just cost a Node install for
# nothing; the frontend gets its own static build/deploy, unrelated to this image.
COPY src/1-API/Humaid.RiskGovernance.AdminUI.Web/ src/1-API/Humaid.RiskGovernance.AdminUI.Web/
COPY src/2-Infrastructure/Humaid.RiskGovernance.AdminUI.Infrastructure/ src/2-Infrastructure/Humaid.RiskGovernance.AdminUI.Infrastructure/
COPY src/3-Service/Humaid.RiskGovernance.AdminUI.Services/ src/3-Service/Humaid.RiskGovernance.AdminUI.Services/
COPY src/3-Service/Humaid.RiskGovernance.AdminUI.AI/ src/3-Service/Humaid.RiskGovernance.AdminUI.AI/
COPY src/4-Persistence/Humaid.RiskGovernance.AdminUI.DA/ src/4-Persistence/Humaid.RiskGovernance.AdminUI.DA/

RUN dotnet publish src/1-API/Humaid.RiskGovernance.AdminUI.Web/Humaid.RiskGovernance.AdminUI.Web.csproj \
    -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "Humaid.RiskGovernance.AdminUI.Web.dll"]
