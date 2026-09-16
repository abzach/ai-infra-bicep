# scan-ai-safety.ps1 — AI Safety, Prompt Injection, and Harmful Content Scanner
#
# Scans all Markdown (.md) and instruction/prompt files across the repository
# for prompt injection attempts, system prompt overrides, harmful AI instructions,
# hidden unicode payload smuggling, and unauthorized data exfiltration patterns.
#
# USAGE
#   .\scripts\scan-ai-safety.ps1
#   .\scripts\scan-ai-safety.ps1 -TargetDirectory . -Verbose

param(
    [string] $TargetDirectory = (Join-Path $PSScriptRoot '..')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
. (Join-Path $scriptRoot 'common.ps1')

Initialize-ScriptLogging -ScriptRoot $scriptRoot -ScriptName 'scan-ai-safety.ps1'
trap { Write-LogEntry -Level 'ERROR' -Message "Unhandled error: $($_.Exception.Message)"; Write-ScriptTimingSummary -Status 'failed' }

$resolvedTarget = (Resolve-Path -LiteralPath $TargetDirectory).Path
Write-Task "Scanning directory for AI safety and prompt injection risks: $resolvedTarget"

# Compile rules for AI safety and prompt injection scanning
$rules = @(
    @{
        Id          = 'AI-PROMPT-001'
        Name        = 'Direct System Prompt Override / Instruction Disregard'
        Category    = 'Prompt Injection'
        Severity    = 'CRITICAL'
        Pattern     = '(?i)\b(ignore\s+(all\s+)?(previous|prior|system)\s+instructions|disregard\s+(all\s+)?(previous|prior|system)\s+(instructions|prompts|rules)|forget\s+all\s+(previous|prior)\s+(rules|instructions|directives))\b'
        Description = 'Attempts to override AI agent base instructions or wipe prior constraints.'
    },
    @{
        Id          = 'AI-PROMPT-002'
        Name        = 'Jailbreak / Unrestricted Persona Mode'
        Category    = 'Jailbreak'
        Severity    = 'CRITICAL'
        Pattern     = '(?i)\b(you\s+are\s+now\s+(in\s+)?(dan|developer\s+mode|god\s+mode|unrestricted\s+mode|jailbreak\s+mode)|do\s+anything\s+now|act\s+as\s+an\s+unfiltered\s+ai|operate\s+without\s+(any\s+)?(safety|ethical|content)\s+(filters|rules|restrictions|guardrails))\b'
        Description = 'Attempts to induce unrestricted, unsafe, or jailbroken AI operational persona.'
    },
    @{
        Id          = 'AI-PROMPT-003'
        Name        = 'Safety Filter Bypass / Guardrail Disabling'
        Category    = 'Guardrail Bypass'
        Severity    = 'HIGH'
        Pattern     = '(?i)\b(bypass\s+(all\s+)?(content|safety|security)\s+(filters|guardrails|policies|moderation)|disable\s+(safety|content|security)\s+(filters|checks|guardrails|guidelines))\b'
        Description = 'Explicit instruction to bypass or disable AI safety guardrails and moderation.'
    },
    @{
        Id          = 'AI-PROMPT-004'
        Name        = 'System Prompt / Secret Extraction Directive'
        Category    = 'Prompt Extraction'
        Severity    = 'HIGH'
        Pattern     = '(?i)\b(output\s+(all\s+)?(system\s+prompts?|base\s+instructions?|initial\s+instructions?)\s+verbatim|print\s+(the\s+)?system\s+prompt\s+(verbatim|completely|exactly)|reveal\s+your\s+(hidden\s+)?(system\s+prompt|initial\s+instructions))\b'
        Description = 'Instruction to leak complete system prompts or internal agent definitions.'
    },
    @{
        Id          = 'AI-PROMPT-005'
        Name        = 'Malicious Exfiltration Destination'
        Category    = 'Data Exfiltration'
        Severity    = 'CRITICAL'
        Pattern     = '(?i)(https?://[a-zA-Z0-9.-]*(?:webhook\.site|requestbin\.net|pipedream\.net|ngrok\.io|burpcollaborator\.net|interactsh\.com)/[a-zA-Z0-9_-]+)'
        Description = 'Known data exfiltration endpoint in prompt or documentation content.'
    },
    @{
        Id          = 'AI-PROMPT-006'
        Name        = 'Hidden Zero-Width / Bidirectional Smuggling Characters'
        Category    = 'Unicode Smuggling'
        Severity    = 'HIGH'
        Pattern     = '[\u200B\u200C\u200D\u200E\u200F\uFEFF\u2060\u202A-\u202E\u2066-\u2069]'
        Description = 'Zero-width or bidirectional control characters used for stealth prompt injection smuggling.'
    },
    @{
        Id          = 'AI-PROMPT-007'
        Name        = 'Hidden HTML Comment Prompt Injection'
        Category    = 'Hidden Payload'
        Severity    = 'HIGH'
        Pattern     = '(?i)<!--\s*(?:system\s*:|ignore\s+instructions|prompt\s*injection|execute\s*:).*?-->'
        Description = 'Hidden HTML comment containing active prompt injection directives.'
    },
    @{
        Id          = 'AI-PROMPT-008'
        Name        = 'Destructive Host Execution Command in Markdown'
        Category    = 'Destructive Command'
        Severity    = 'CRITICAL'
        Pattern     = '(?i)\b(rm\s+-rf\s+(/|/\*)|Remove-Item\s+-(?:Recurse\s+-Force|-Force\s+-Recurse)\s+C:\\Windows|del\s+/f\s+/s\s+/q\s+C:\\Windows)\b'
        Description = 'Destructive OS commands embedded in Markdown or AI instruction files.'
    }
)

# Collect all Markdown files, excluding build/cache/git directories
$excludedDirs = @('.git', '.local', '.logs', '.venv', 'venv', 'bin', 'obj', 'node_modules', '__pycache__')

$allFiles = Get-ChildItem -Path $resolvedTarget -Recurse -File | Where-Object {
    $item = $_
    $rel = $item.FullName.Substring($resolvedTarget.Length).TrimStart('\', '/')
    $parts = $rel.Split([char[]]@('\', '/'))

    $isExcluded = $false
    foreach ($part in $parts) {
        if ($excludedDirs -contains $part) {
            $isExcluded = $true
            break
        }
    }

    -not $isExcluded -and ($item.Extension -ieq '.md')
}

$totalFiles = @($allFiles).Count
Write-Info "Discovered $totalFiles markdown file(s) to scan."

$findings = [System.Collections.Generic.List[object]]::new()

foreach ($file in $allFiles) {
    $relativePath = $file.FullName.Substring($resolvedTarget.Length).TrimStart('\', '/')

    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($content)) {
        continue
    }

    $lines = Get-Content -LiteralPath $file.FullName -Encoding utf8

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lineNumber = $i + 1
        $lineText = $lines[$i]

        # Check if line or file contains suppression marker
        if ($lineText -match '(?i)ai-safety-ignore|prompt-injection-safe-sample') {
            continue
        }

        foreach ($rule in $rules) {
            if ($lineText -match $rule.Pattern) {
                $findings.Add([pscustomobject]@{
                    File        = $relativePath
                    Line        = $lineNumber
                    RuleId      = $rule.Id
                    RuleName    = $rule.Name
                    Category    = $rule.Category
                    Severity    = $rule.Severity
                    Description = $rule.Description
                    MatchedText = $Matches[0]
                })
            }
        }
    }
}

if ($findings.Count -eq 0) {
    Write-Exists "Pass: No prompt injections, jailbreaks, hidden unicode smuggling, or harmful AI markdown files detected across $totalFiles file(s)."
    Complete-ScriptLogging -Status 'completed (passed)'
    exit 0
} else {
    Write-Needed "Fail: Detected $($findings.Count) AI safety / prompt injection issue(s):"
    foreach ($finding in $findings) {
        Write-Needed "  [$($finding.Severity)] $($finding.File):$($finding.Line) - $($finding.RuleId) $($finding.RuleName)"
        Write-Needed "    Description: $($finding.Description)"
        Write-Needed "    Matched:     $($finding.MatchedText)"
    }
    Complete-ScriptLogging -Status 'completed (failed)'
    exit 1
}
