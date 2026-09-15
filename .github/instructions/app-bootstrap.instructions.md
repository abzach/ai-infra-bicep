---
applyTo: "app/**/*.py,app/requirements.txt,app/.env.example,scripts/setup.ps1,scripts/deploy.ps1"
---

# App bootstrap and runtime changes

- Keep the Python app on managed identity authentication. Do not add Azure OpenAI API keys.
- Preserve `AZURE_CLIENT_ID` so `DefaultAzureCredential` selects the dedicated VM user-assigned identity.
- Keep `.env` generation on the VM through `first-run.ps1`, using Key Vault over the private endpoint.
- If runtime configuration changes, update `.env.example`, `app/README.md`, secret sync in `deploy.ps1`, and config-version hashing.
- If deployed files change, ensure the app content hash changes so `deploy.ps1` reboots the VM package only when needed.
- Validate Python changes with the smallest local parse/test available and use deployed `Smoke` or `ChatDual` modes when the environment is available.

