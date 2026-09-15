# Python Terminal Chat Application

This document details the architecture, persona engine, authentication flow, and operational usage of the Python Chat Application located under `app/`.

## Architecture Overview

The application runs directly on the Windows Jumpbox VM in `C:\ChatApp\` and connects to Azure OpenAI over private endpoints without API keys.

```
                  ┌────────────────────────────────────────┐
                  │          Terminal User Prompt          │
                  └───────────────────┬────────────────────┘
                                      │
                         ThreadPoolExecutor (workers=2)
                                      │
                 ┌────────────────────┴────────────────────┐
                 ▼                                         ▼
         Persona: Keith (Senior Dev)               Persona: Tim (Architect)
         Model: gpt-4.1-mini                       Model: gpt-4.1-nano
         Style: Concise, code-first                Style: Scalability, trade-offs
                 │                                         │
                 └────────────────────┬────────────────────┘
                                      │
                                      ▼
                        Side-by-Side Rich Terminal UI
```

### Script Inventory

| File | Purpose | Execution Mode |
|---|---|---|
| `app/chat.py` | Dual-persona interactive terminal chat | Interactive session |
| `app/test.py` | Single-shot smoke test for validation | Non-interactive validation |
| `app/requirements.txt` | Python package dependencies | Setup / bootstrap |
| `app/.env.example` | Environment variable reference template | Configuration |

## Personas & Multi-Model Inference

`chat.py` sends every user prompt simultaneously to two model deployments using `concurrent.futures.ThreadPoolExecutor(max_workers=2)`:

| Persona Name | Persona Role | Model Deployment | Persona Tone & Guidance |
|---|---|---|---|
| **Keith** | Senior Software Developer | Primary (`gpt-4.1-mini`) | Concise, code-focused, concrete implementation details |
| **Tim** | Software Architect | Secondary (`gpt-4.1-nano`) | High-level system design, trade-offs, security, scalability |

## Configuration & Environment Variables

The app reads environment variables from `.env` (`C:\ChatApp\.env` on the VM or `app/.env` for local development):

| Environment Variable | Description | Source / Default |
|---|---|---|
| `AZURE_KEY_VAULT_URL` | Key Vault URL | Retrieved during VM bootstrap |
| `AZURE_CLIENT_ID` | Client ID of the VM User-Assigned Managed Identity | User-Assigned Identity (`mi-...-vm-...`) |
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI resource endpoint URL | OpenAI Account (`https://oai-...openai.azure.com/`) |
| `AZURE_OPENAI_DEPLOYMENT` | Primary model deployment name | `gpt-4-1-mini` |
| `AZURE_OPENAI_SECONDARY_DEPLOYMENT` | Secondary model deployment name | `gpt-4-1-nano` |
| `AZURE_OPENAI_API_VERSION` | Azure OpenAI REST API version | `2025-01-01-preview` |
| `CONFIG_VERSION` | Deployment fingerprint | Used by `first-run.ps1` to detect configuration drift |

## Authentication Flow

1. The app instantiates `DefaultAzureCredential(managed_identity_client_id=AZURE_CLIENT_ID)`.
2. Acquires an Entra ID bearer token for scope `https://cognitiveservices.azure.com/.default`.
3. Passes the token provider directly to `openai.AzureOpenAI(azure_ad_token_provider=...)`.
4. No static OpenAI API keys or credentials exist in code, disk, or memory.

## Terminal Commands (`chat.py`)

| Command | Action |
|---|---|
| `/new` | Resets conversation history for both personas and starts a fresh thread |
| `/help` | Displays available interactive commands |
| `/exit` | Gracefully closes the chat application |

## Connectivity Verification (`test.py`)

`test.py` validates connectivity and RBAC permissions with an exit code suitable for automated pipelines:
- **Success:** Exit code `0`
- **Failure:** Exit code `1`

```powershell
python test.py --prompt "Reply with OK only."
```

## Related Documentation

- [Azure OpenAI Documentation](azure-openai.md)
- [Managed Identity Documentation](managed-identity.md)
- [Virtual Machine Documentation](virtual-machine.md)
- [Documentation Index](index.md)
