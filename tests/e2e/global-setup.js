// Guards every run: if the Workbench API is not reachable, fail loudly here rather than letting
// the suite report a misleading result.
//
// This matters specifically because api/authorization.spec.js uses test.fail() to record known
// security gaps. A test.fail() test "passes" whenever it fails for ANY reason - including
// ECONNREFUSED. Without this check, running the suite with nothing listening on :5210 would
// produce a full green board that proves nothing at all.
export default async function globalSetup() {
  const baseUrl = process.env.API_BASE_URL ?? 'http://localhost:5210';
  const pingUrl = `${baseUrl}/api/Ping`;

  let response;
  try {
    response = await fetch(pingUrl);
  } catch (error) {
    throw new Error(
      `Cannot reach the Workbench API at ${pingUrl} (${error.message}).\n\n` +
        `Start the stack first:\n` +
        `  1. bash ops/setup-local-db.sh                                              (Postgres + Azurite)\n` +
        `  2. dotnet run --project src/6-MockExternalSystems/Humaid.RiskGovernance.MockSystems\n` +
        `  3. dotnet run --project src/1-API/Humaid.RiskGovernance.AdminUI.Web\n\n` +
        `See tests/e2e/README.md.`,
    );
  }

  if (!response.ok) {
    throw new Error(`GET ${pingUrl} returned ${response.status}; expected 200 before running the suite.`);
  }
}
