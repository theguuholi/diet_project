# CoreComponents: large generated UI helpers; excluded from threshold like many Phoenix apps.
# Production API clients: require real external credentials to exercise directly.
# Their contracts are tested through Mox behaviour mocks in the unit tests.
[
  DietProject.Application,
  DietProjectWeb.CoreComponents,
  DietProjectWeb.Layouts,
  DietProject.Repo,
  DietProjectWeb.Telemetry,
  Mix.Tasks.Coverage.Index,
  DietProjectWeb.ErrorHTML,
  DietProjectWeb.PageHTML,
  DietProject.AI.ClaudeClient,
  DietProject.AI.WhisperClient,
  DietProject.Integrations.R2Client,
  DietProject.Integrations.WhatsAppClient
]
