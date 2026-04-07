import concurrent.futures
import os
import sys
import threading
from typing import List, Dict, Tuple, Optional

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from dotenv import load_dotenv
from openai import AzureOpenAI, AuthenticationError, PermissionDeniedError, RateLimitError, APIConnectionError, APIStatusError

from rich.console import Console
from rich.panel import Panel
from rich.markdown import Markdown
from rich.layout import Layout
from rich.prompt import Prompt
from rich.text import Text
from rich.live import Live
from rich.spinner import Spinner
from rich import box
from rich.table import Table

console = Console()

class Persona:
    def __init__(self, name: str, icon: str, color: str, style: str, role: str, description: str):
        self.name = name
        self.icon = icon
        self.color = color
        self.style = style
        self.role = role
        self.description = description

    @property
    def display_name(self) -> str:
        return f"{self.icon} {self.name} ({self.role})"

PERSONAS = {
    'user': Persona(
        name="User",
        icon="👤",
        color="blue",
        style="bold blue",
        role="User",
        description=""
    ),
    'keith': Persona(
        name="Keith",
        icon="👤",
        color="green",
        style="bold green",
        role="Developer",
        description=(
            "You are Keith, a pragmatic senior developer. "
            "You prefer concise, code-focused answers. "
            "You care about implementation details, performance, and best practices. "
            "You are direct and efficient."
        )
    ),
    'tim': Persona(
        name="Tim",
        icon="👤",
        color="red",
        style="bold red",
        role="Architect",
        description=(
            "You are Tim, a software architect. "
            "You focus on high-level design, system patterns, trade-offs, and scalability. "
            "You like to explain the 'why' behind decisions. "
            "You are thoughtful and comprehensive."
        )
    )
}

LOGO_ART = r"""
        ,----------------------------------------------------,
       /  .------------------------------------------------.  \
      /  /                                                  \  \
     |  |        .----------------------------------.        |  |
     |  |       /          /|            |\          \       |  |
     |  |      /          / |            | \          \      |  |
     |  |     |          |  |            |  |          |     |  |
     |  |     |   [||]   |  |            |  |   [||]   |     |  |
     |  |     |          |  |            |  |          |     |  |
     |  |     |          |  |            |  |          |     |  |
     |  |      \          \ |            | /          /      |  |
     |  |       \          \|            |/          /       |  |
     |  |        `----------------------------------'        |  |
     |  |                                                    |  |
     |  |                  [ ============ ]                  |  |
     |  |                                                    |  |
      \  \                                                  /  /
       \  `------------------------------------------------'  /
        `----------------------------------------------------'
"""

BACKSTORY = """
[bold cyan]SYSTEM INITIALIZED...[/bold cyan]

You have entered [bold white]The Abzach Construct[/bold white].

[dim]This interaction is only possible because you successfully deployed the underlying Azure AI Foundry infrastructure to host these models.[/dim]

Two specialized AI constructs inhabit this space to aid your journey:

[green]👤 Keith[/green]: The builder. A master of syntax and efficiency.
[red]👤 Tim[/red]: The architect. A visionary of structure and scale.

[bold white]Possibilities:[/bold white]
1. [cyan]Biology[/cyan]: Design proteins with AlphaFold.
2. [cyan]Climate[/cyan]: Optimize energy grids with reinforcement learning.
3. [cyan]Art[/cyan]: Generate textures for game assets.
4. [cyan]Space[/cyan]: Navigate rovers with autonomous vision.
5. [cyan]Code[/cyan]: Refactor legacy monoliths into microservices.

[italic cyan]Created to inspire you to learn, test, design, and reinvent—contributing to the AI landscape evolution as part of the revolution already underway.[/italic cyan]

They listen together. They answer together. 
Press [bold white]Enter[/bold white] to broadcast your thoughts.
"""

def print_logo():
    """Print the startup ASCII logo."""
    console.print(Panel(
        Text(LOGO_ART, style="bold cyan", justify="center"),
        box=box.HEAVY,
        border_style="cyan",
        title="[bold white]ABZACH CHAT[/bold white]",
        subtitle="[dim]v2.0 • abzach@microsoft.com[/dim]"
    ))

def print_backstory():
    """Print the narrative introduction."""
    console.print(Panel(
        BACKSTORY,
        box=box.ROUNDED,
        border_style="dim white",
        padding=(1, 2)
    ))
    console.print("[dim]Type [bold]/help[/bold] for available commands.[/dim]\n")

def print_help():
    """Display supported commands."""
    help_text = """
    [bold white]Available commands:[/bold white]
    
    [bold cyan]/new[/bold cyan]   - Clear the session and restart (replays backstory).
    [bold cyan]/help[/bold cyan]  - Show this help menu.
    [bold cyan]/exit[/bold cyan]  - Disconnect from the construct.
    """
    console.print(Panel(help_text, border_style="dim", box=box.ROUNDED))

def load_settings() -> Dict[str, str]:
    """Load model endpoint and deployment names from the .env file."""
    load_dotenv()

    endpoint = os.getenv('AZURE_OPENAI_ENDPOINT', '').strip()
    primary_deployment = os.getenv('AZURE_OPENAI_DEPLOYMENT', '').strip()
    secondary_deployment = os.getenv('AZURE_OPENAI_SECONDARY_DEPLOYMENT', '').strip()
    api_version = os.getenv('AZURE_OPENAI_API_VERSION', '2025-01-01-preview').strip()

    if not endpoint or not primary_deployment:
        raise ValueError(
            'Missing required configuration. Ensure AZURE_OPENAI_ENDPOINT and '
            'AZURE_OPENAI_DEPLOYMENT are set in .env (run the AI Chat shortcut '
            'to create it automatically on first launch).'
        )

    return {
        'endpoint': endpoint,
        'primary_deployment': primary_deployment,
        'secondary_deployment': secondary_deployment,
        'api_version': api_version,
    }


# Maximum number of user/assistant message pairs kept in the sliding context window.
# The system prompt is always prepended and does not count against this limit.
MAX_HISTORY_PAIRS = 20


def _trim_history(messages: List[Dict[str, str]]) -> List[Dict[str, str]]:
    """Return at most MAX_HISTORY_PAIRS user/assistant pairs from the end of history."""
    non_system = [m for m in messages if m['role'] != 'system']
    if len(non_system) > MAX_HISTORY_PAIRS * 2:
        non_system = non_system[-(MAX_HISTORY_PAIRS * 2):]
    return non_system


def _ask_model(
    client: AzureOpenAI,
    deployment: str,
    messages: List[Dict[str, str]],
    persona: Persona
) -> Tuple[str, str]:
    """
    Query one model and return (deployment_name, answer).
    Injects the persona's system prompt and trims history to MAX_HISTORY_PAIRS.
    """
    system_message = {
        'role': 'system',
        'content': f"You are {persona.name}, a {persona.role}. {persona.description}"
    }

    api_messages = [system_message] + _trim_history(messages)

    try:
        response = client.chat.completions.create(
            model=deployment,
            messages=api_messages,
            temperature=0.7,
            max_tokens=800,
        )
        answer = response.choices[0].message.content or ''
        return deployment, answer
    except (AuthenticationError, PermissionDeniedError) as e:
        return deployment, f"[Auth error] Check that the managed identity has the Cognitive Services OpenAI User role. ({e.status_code})"
    except RateLimitError as e:
        return deployment, f"[Rate limited] The deployment quota is exhausted. Wait and retry. ({e.status_code})"
    except APIConnectionError as e:
        return deployment, f"[Network error] Could not reach the Azure OpenAI endpoint. Check VPN/network connectivity. ({type(e).__name__})"
    except APIStatusError as e:
        return deployment, f"[API error {e.status_code}] {e.message}"
    except Exception as e:
        return deployment, f"[Unexpected error] {type(e).__name__}: {e}"


def display_response(persona: Persona, content: str):
    """Render a model's response in a styled panel."""
    md = Markdown(content)
    panel = Panel(
        md,
        title=f"{persona.display_name}",
        border_style=persona.style,
        box=box.ROUNDED,
        expand=False,
        padding=(1, 2)
    )
    console.print(panel)
    console.print()


def run_chat(
    client: AzureOpenAI,
    primary_dep: str,
    secondary_dep: str,
) -> None:
    """Run the main chat loop."""
    
    console.clear()
    print_logo()

    user_name = Prompt.ask("\n[bold blue]Identify yourself[/bold blue] (press Enter for 'Explorer') [dim](You)[/dim]", default="Explorer", show_default=False)
    PERSONAS['user'].name = user_name

    console.print(f"\n[dim]Identity verified: {PERSONAS['user'].display_name}[/dim]\n")
    print_backstory()

    while True:
        conversation_history: List[Dict[str, str]] = []

        dep_map = {}
        if primary_dep:
            dep_map[primary_dep] = PERSONAS['keith']
        if secondary_dep:
            dep_map[secondary_dep] = PERSONAS['tim']

        active_deployments = [d for d in [primary_dep, secondary_dep] if d]

        def build_progress_table(status_map: Dict[str, str]) -> Table:
            """Render a status row per deployment; shows spinner while status contains '...'."""
            table = Table(box=None, show_header=False, show_edge=False, padding=(0, 1))
            for dep in active_deployments:
                persona = dep_map[dep]
                status = status_map[dep]
                if '...' in status:
                    spinner = Spinner('dots', style=persona.style)
                    table.add_row(spinner, Text(f"{persona.name} is {status}", style=persona.style))
                else:
                    table.add_row('✓', Text(f"{persona.name} is ready", style='dim'))
            return table

        if active_deployments:
            console.print("[dim]Initializing constructs...[/dim]")
            
            status_map = {dep: "connecting..." for dep in active_deployments}
            
            results = {}
            with Live(build_progress_table(status_map), refresh_per_second=10, transient=True) as live:
                futures = {}
                with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
                    for dep in active_deployments:
                        persona = dep_map[dep]
                        
                        intro_prompt = (
                            f"Briefly introduce yourself in 1-2 sentences. "
                            f"Explicitly mention you are powered by the '{dep}' model. "
                            f"State what you are good for."
                        )
                        intro_msgs = [{'role': 'user', 'content': intro_prompt}]
                        
                        futures[executor.submit(_ask_model, client, dep, intro_msgs, persona)] = dep

                    for future in concurrent.futures.as_completed(futures):
                        dep = futures[future]
                        try:
                            _, answer = future.result()
                            results[dep] = answer
                            status_map[dep] = "online"
                        except Exception as ex:
                            results[dep] = f"Error: {ex}"
                            status_map[dep] = "error"
                        
                        live.update(build_progress_table(status_map))

            for dep in active_deployments:
                if dep in results:
                    persona = dep_map[dep]
                    display_response(persona, results[dep])
                    conversation_history.append({'role': 'assistant', 'content': f"[{persona.name}]: {results[dep]}"})

        while True:
            try:
                user_input = Prompt.ask(f"\n[{PERSONAS['user'].style}]{PERSONAS['user'].icon} {PERSONAS['user'].name}[/]")
            except (KeyboardInterrupt, EOFError):
                console.print("\n[dim]Disconnecting...[/dim]")
                return

            if not user_input.strip():
                continue
            
            cmd = user_input.strip().lower()
            
            if cmd == '/exit':
                console.print("[bold red]Disconnecting from the construct. Goodbye.[/bold red]")
                return
            
            if cmd == '/new':
                console.clear()
                print_logo()
                console.print(f"\n[dim]Identity verified: {PERSONAS['user'].display_name}[/dim]\n")
                print_backstory()
                break
                
            if cmd == '/help':
                print_help()
                continue
                
            if cmd in ('exit', 'quit'):
                console.print("[dim]Tip: Use [bold]/exit[/bold] to quit.[/dim]")
                return
                
            if cmd == 'clear':
                console.print("[dim]Tip: Use [bold]/new[/bold] to restart the session.[/dim]")
                continue

            conversation_history.append({'role': 'user', 'content': user_input})

            active_deployments = [d for d in [primary_dep, secondary_dep] if d]
            status_map = {dep: "thinking..." for dep in active_deployments}
            
            with Live(build_progress_table(status_map), refresh_per_second=10, transient=True) as live:
                futures = {}
                results = {}
                
                with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
                    for dep in active_deployments:
                        persona = dep_map[dep]
                        futures[executor.submit(_ask_model, client, dep, conversation_history, persona)] = dep

                    for future in concurrent.futures.as_completed(futures):
                        dep = futures[future]
                        try:
                            _, answer = future.result()
                            results[dep] = answer
                            status_map[dep] = "done"
                        except Exception as ex:
                            results[dep] = f"Error: {ex}"
                            status_map[dep] = "error"
                        
                        live.update(build_progress_table(status_map))

            for dep in active_deployments:
                if dep in results:
                    persona = dep_map[dep]
                    display_response(persona, results[dep])
                    conversation_history.append({'role': 'assistant', 'content': f"[{persona.name}]: {results[dep]}"})


import traceback

def main() -> int:
    try:
        settings = load_settings()
    except Exception as ex:
        console.print(f"[bold red]Configuration error:[/bold red] {ex}")
        return 1

    try:
        token_provider = get_bearer_token_provider(
            DefaultAzureCredential(), 'https://cognitiveservices.azure.com/.default'
        )
        client = AzureOpenAI(
            azure_endpoint=settings['endpoint'],
            azure_ad_token_provider=token_provider,
            api_version=settings['api_version'],
        )
        
        run_chat(
            client,
            primary_dep=settings['primary_deployment'],
            secondary_dep=settings['secondary_deployment'],
        )
        return 0
    except Exception:
        console.print("[bold red]Failed to initialize chat client:[/bold red]")
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
