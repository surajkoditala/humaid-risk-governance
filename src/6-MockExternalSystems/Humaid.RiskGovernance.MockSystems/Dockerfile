# Build context is the repo ROOT, same convention as the Workbench's Dockerfile, even though this
# project has no sibling ProjectReferences - deliberately: Mock Systems is NOT part of the
# Workbench (see docs/architecture/architecture-mapping.md), so it never references any
# 1-API/2-Infrastructure/3-Service/4-Persistence project. From the repo root:
#   docker build -f src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/Dockerfile -t humaid-mocksystems .

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Optional: trust an extra local root CA before any network call - see the Workbench Dockerfile's
# comment and ops/certs/README.md for why this is here (SSL-inspecting corporate proxies).
COPY ops/certs/ /usr/local/share/ca-certificates/extra/
RUN find /usr/local/share/ca-certificates/extra/ -name '*.crt' -o -name '*.pem' | grep -q . && update-ca-certificates || true

COPY src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/*.csproj src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/
RUN dotnet restore src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/Humaid.RiskGovernance.MockSystems.csproj

COPY src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/ src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/

RUN dotnet publish src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems/Humaid.RiskGovernance.MockSystems.csproj \
    -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

# Run as the non-root `app` user that the .NET 8+ aspnet images ship (APP_UID is set by the
# base image). Port 8080 is > 1024, so no privileges are needed to bind it.
USER $APP_UID

ENTRYPOINT ["dotnet", "Humaid.RiskGovernance.MockSystems.dll"]
