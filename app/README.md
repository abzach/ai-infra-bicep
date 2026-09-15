# Chat App

Python terminal application for Azure OpenAI running on the jumpbox VM. Two files handle distinct responsibilities:

| File | Purpose |
|---|---|
| `chat.py` | Interactive dual-persona terminal chat session |
| `test.py` | Single-shot smoke test for connectivity validation |

The deployed application uses **managed identity authentication**. Local development uses the available `DefaultAzureCredential` chain, such as Azure CLI credentials. No Azure OpenAI API keys are stored or used.

## chat.py

Interactive terminal that queries **two Azure OpenAI model deployments in parallel** and renders their responses side-by-side in a rich styled UI

### Personas

| Persona | Role | Style |
|---|---|---|
| **Keith** | Senior Developer | Concise, code-focused, implementation-driven |
| **Tim** | Software Architect | High-level design, trade-offs, scalability |

Both personas receive your message simultaneously via `concurrent.futures.ThreadPoolExecutor(max_workers=2)` and their responses are streamed back independently.

### Session commands

| Command | Action |
|---|---|
| `/new` | Clear conversation history and start fresh |
| `/help` | Show available commands |
| `/exit` | Quit the application |

## test.py

A single-shot connectivity test. Sends one prompt to the primary model deployment and exits with code `0` on success or `1` on failure. Useful for validating that the environment is fully provisioned and that the managed identity has the required `Cognitive Services OpenAI User` RBAC role.

```powershell
# Default test prompt
python test.py

# Custom prompt
python test.py --prompt "Summarise the CAP theorem in one sentence."
```

## Configuration

Both scripts read configuration from `.env`. Local development uses `app/.env`; the deployed VM uses `C:\ChatApp\.env`. On first desktop launch, `first-run.ps1` signs the administrator in with Azure CLI and reads the values from Key Vault through its private endpoint. The Python application itself uses the VM's user-assigned managed identity for Azure OpenAI calls.

`chat.py`, `test.py`, and `.env.example` are the source of truth for application settings and defaults. Never commit a populated `.env` file.

| Variable | Description |
|---|---|
| `AZURE_KEY_VAULT_URL` | Key Vault URL recorded by the VM launcher |
| `AZURE_CLIENT_ID` | User-assigned managed identity client ID |
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI resource endpoint URL |
| `AZURE_OPENAI_DEPLOYMENT` | Primary model deployment name |
| `AZURE_OPENAI_SECONDARY_DEPLOYMENT` | Secondary model deployment name |
| `AZURE_OPENAI_API_VERSION` | API version (default: `2025-01-01-preview`) |
| `CONFIG_VERSION` | Deployment-generated fingerprint used by `first-run.ps1` to refresh stale configuration |

## Authentication

`DefaultAzureCredential` is used for authentication. On the VM, `AZURE_CLIENT_ID` ensures the credential resolves to the dedicated user-assigned identity rather than the system-assigned one. During local development, the chain can use an authenticated developer credential such as Azure CLI. A bearer token is obtained for `https://cognitiveservices.azure.com/.default`; the `AzureOpenAI` client receives the token provider directly without an API key.

## Dependencies

Defined in `requirements.txt`:

| Package | Purpose |
|---|---|
| `openai` | Azure OpenAI SDK |
| `azure-identity` | `DefaultAzureCredential` and token provider |
| `python-dotenv` | `.env` file loading |
| `rich` | Terminal UI (panels, markdown, spinners, tables) |
| `colorama` | Windows terminal color compatibility |

## Local development setup

To run or test locally (requires valid Azure credentials and network access to the OpenAI endpoint):

```powershell
# from app/
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

# Smoke test
python test.py --prompt "Reply with OK only."

# Full chat session
python chat.py
```

Deactivate the virtual environment when done:

```powershell
deactivate
```

Update this README whenever the app's runtime behavior, environment variables, or dependencies change; see [../.github/instructions/documentation-sync.instructions.md](../.github/instructions/documentation-sync.instructions.md).
