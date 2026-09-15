# setup.ps1 — VM bootstrap script executed through Azure VM Run Command.

$ErrorActionPreference = 'Stop'

Write-Host "Stopping any running python processes..." -ForegroundColor Yellow
Stop-Process -Name "python", "pythonw" -Force -ErrorAction SilentlyContinue

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$appDir = 'C:\ChatApp'
$logFile = 'C:\ChatApp\setup.log'
$windowsPowerShellPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

New-Item -ItemType Directory -Force -Path $appDir | Out-Null

function Write-Log {
    param(
        [string]$Message,
        [System.ConsoleColor]$Color = 'DarkGray'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "$timestamp  $Message"
    Write-Host $entry -ForegroundColor $Color
    Add-Content -Path $logFile -Value $entry -ErrorAction SilentlyContinue
}

function Update-SessionPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $userPath    = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    $env:PATH = ($machinePath, $userPath | Where-Object { $_ }) -join ';'
}

function Install-Python {
    Update-SessionPath
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        $versionOutput = & python --version 2>&1
        if ($versionOutput -match 'Python 3\.(\d+)\.' -and [int]$Matches[1] -ge 10) {
            Write-Log "Python already installed: $versionOutput - skipping install." -Color Green
            return
        }
        Write-Log "Installed Python version ($versionOutput) is below 3.10 - will upgrade." -Color Red
    } else {
        Write-Log 'Python not found on PATH - installing Python 3.12...' -Color Red
    }

    $pythonInstallerUrl  = 'https://www.python.org/ftp/python/3.12.9/python-3.12.9-amd64.exe'
    $pythonInstallerPath = 'C:\Windows\Temp\python-3.12.9-amd64.exe'

    Write-Log "Downloading Python installer from $pythonInstallerUrl..." -Color Blue
    Invoke-WebRequest -Uri $pythonInstallerUrl -OutFile $pythonInstallerPath -UseBasicParsing
    Write-Log 'Download complete. Running silent install...' -Color Blue

    $installArgs = '/quiet InstallAllUsers=1 PrependPath=1 Include_test=0 Include_launcher=1 InstallLauncherAllUsers=1'
    $proc = Start-Process -FilePath $pythonInstallerPath -ArgumentList $installArgs -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Log "Error: Python installer exited with code $($proc.ExitCode)." -Color Red
        exit 1
    }

    Update-SessionPath
    Write-Log 'Python 3.12 installed and PATH refreshed.' -Color Green
}

function Install-AzureCli {
    Update-SessionPath
    $azCmd = Get-Command az -ErrorAction SilentlyContinue
    if ($azCmd) {
        Write-Log 'Azure CLI already installed - skipping install.' -Color Green
        return
    }

    $azCliMsiUrl  = 'https://aka.ms/installazurecliwindows'
    $azCliMsiPath = 'C:\Windows\Temp\AzureCLI.msi'

    Write-Log "Downloading Azure CLI MSI from $azCliMsiUrl..." -Color Blue
    Invoke-WebRequest -Uri $azCliMsiUrl -OutFile $azCliMsiPath -UseBasicParsing
    Write-Log 'Download complete. Running silent install...' -Color Blue

    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i `"$azCliMsiPath`" /quiet /norestart" -Wait -PassThru
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        Write-Log "Error: Azure CLI MSI installer exited with code $($proc.ExitCode)." -Color Red
        exit 1
    }

    Update-SessionPath
    Write-Log 'Azure CLI installed and PATH refreshed.' -Color Green
}

function Install-PowerShell7 {
    try {
    Update-SessionPath
    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshCmd) {
        Write-Log 'PowerShell 7 already installed - skipping install.' -Color Green
        return
    }

    $pwshMsiUrl = 'https://aka.ms/pwsh-msi'
    $pwshMsiPath = 'C:\Windows\Temp\PowerShell-7-latest.msi'

    Write-Log "Downloading PowerShell 7 MSI from $pwshMsiUrl..." -Color Blue
    Invoke-WebRequest -Uri $pwshMsiUrl -OutFile $pwshMsiPath -UseBasicParsing
    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i `"$pwshMsiPath`" /quiet /norestart" -Wait -PassThru
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        Write-Log "Warning: PowerShell 7 installer exited with code $($proc.ExitCode)." -Color Red
        return
    }

    Update-SessionPath
    Write-Log 'PowerShell 7 installation completed.' -Color Green
    } catch {
        Write-Log "Warning: PowerShell 7 installation failed (non-fatal): $_" -Color Red
    }
}

function Install-Git {
    try {
    Update-SessionPath
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        Write-Log 'Git already installed - skipping install.' -Color Green
        return
    }

    $gitInstallerUrl = 'https://github.com/git-for-windows/git/releases/latest/download/Git-64-bit.exe'
    $gitInstallerPath = 'C:\Windows\Temp\Git-64-bit.exe'

    Write-Log "Downloading Git installer from $gitInstallerUrl..." -Color Blue
    Invoke-WebRequest -Uri $gitInstallerUrl -OutFile $gitInstallerPath -UseBasicParsing
    $proc = Start-Process -FilePath $gitInstallerPath -ArgumentList '/VERYSILENT /NORESTART /NOCANCEL' -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Log "Warning: Git installer exited with code $($proc.ExitCode)." -Color Red
        return
    }

    Update-SessionPath
    Write-Log 'Git installation completed.' -Color Green
    } catch {
        Write-Log "Warning: Git installation failed (non-fatal): $_" -Color Red
    }
}

function Install-VSCode {
    try {
    Update-SessionPath
    $codeCmd = Get-Command code -ErrorAction SilentlyContinue
    if ($codeCmd) {
        Write-Log 'Visual Studio Code already installed - skipping install.' -Color Green
        return
    }

    $codeInstallerUrl = 'https://update.code.visualstudio.com/latest/win32-x64/stable'
    $codeInstallerPath = 'C:\Windows\Temp\VSCodeSetup-x64.exe'

    Write-Log "Downloading VS Code installer from $codeInstallerUrl..." -Color Blue
    Invoke-WebRequest -Uri $codeInstallerUrl -OutFile $codeInstallerPath -UseBasicParsing
    $proc = Start-Process -FilePath $codeInstallerPath -ArgumentList '/VERYSILENT /NORESTART /MERGETASKS=!runcode' -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Log "Warning: VS Code installer exited with code $($proc.ExitCode)." -Color Red
        return
    }

    Update-SessionPath
    Write-Log 'VS Code installation completed.' -Color Green
    } catch {
        Write-Log "Warning: VS Code installation failed (non-fatal): $_" -Color Red
    }
}

function Install-BicepCli {
    try {
    Update-SessionPath
    $azCmd = Get-Command az -ErrorAction SilentlyContinue
    if (-not $azCmd) {
        Write-Log 'Warning: Azure CLI not available. Skipping Bicep CLI installation.' -Color Red
        return
    }

    az bicep version >$null 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log 'Bicep CLI already installed - upgrading to latest.' -Color Blue
    } else {
        Write-Log 'Bicep CLI not found - installing via Azure CLI.' -Color Blue
    }

    az bicep install --upgrade --only-show-errors
    if ($LASTEXITCODE -eq 0) {
        Write-Log 'Bicep CLI installation completed.' -Color Green
    } else {
        Write-Log 'Warning: Bicep CLI installation failed.' -Color Red
    }
    } catch {
        Write-Log "Warning: Bicep CLI installation failed (non-fatal): $_" -Color Red
    }
}

function Install-AzurePowerShellModules {
    try {
    $azAccountsModule = Get-Module -ListAvailable Az.Accounts -ErrorAction SilentlyContinue
    if ($azAccountsModule) {
        Write-Log 'Azure PowerShell Az module already available - skipping install.' -Color Green
        return
    }

    Write-Log 'Installing Azure PowerShell Az module for all users...' -Color Blue
    $azInstallJob = Start-Job -ScriptBlock {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -ErrorAction SilentlyContinue | Out-Null
        Install-Module -Name Az -Scope AllUsers -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
        'SUCCESS'
    }

    $completedJob = Wait-Job -Job $azInstallJob -Timeout 600
    if ($null -eq $completedJob) {
        Stop-Job -Job $azInstallJob -ErrorAction SilentlyContinue
        Write-Log 'Warning: Azure PowerShell Az module installation timed out after 10 minutes. Continuing.' -Color Red
    } else {
        $jobOutput = Receive-Job -Job $azInstallJob -ErrorAction SilentlyContinue
        if ($jobOutput -contains 'SUCCESS') {
            Write-Log 'Azure PowerShell Az module installation completed.' -Color Green
        } else {
            Write-Log 'Warning: Azure PowerShell Az module installation failed.' -Color Red
        }
    }

    Remove-Job -Job $azInstallJob -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Log "Warning: Azure PowerShell Az module installation failed (non-fatal): $_" -Color Red
    }
}

Write-Log 'Setup started' -Color Blue
Install-Python
Install-AzureCli
Install-PowerShell7
Install-Git
Install-VSCode
Install-BicepCli
Install-AzurePowerShellModules

try {
    Set-TimeZone -Id 'India Standard Time'
    Write-Log 'Timezone set to India Standard Time (IST, UTC+5:30).' -Color Green
} catch {
    Write-Log "Warning: could not set timezone: $($_.Exception.Message)" -Color DarkGray
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
foreach ($file in @('chat.py', 'test.py', 'requirements.txt', 'first-run.ps1')) {
    $src = Join-Path $scriptDir $file
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $appDir -Force
        Write-Log "Copied $file to $appDir."
    } else {
        Write-Log "Warning: $file not found in $scriptDir." -Color Red
    }
}

$venvDir = Join-Path $appDir '.venv'
$venvHashFile = Join-Path $appDir '.venv-hash'
$requirementsFile = Join-Path $appDir 'requirements.txt'

$skipVenvRebuild = $false
if ((Test-Path $venvDir) -and (Test-Path $venvHashFile) -and (Test-Path $requirementsFile)) {
    $currentHash = (Get-FileHash $requirementsFile -Algorithm SHA256).Hash
    $storedHash  = (Get-Content $venvHashFile -Raw).Trim()
    if ($currentHash -eq $storedHash) {
        Write-Log 'requirements.txt unchanged — reusing existing virtual environment.' -Color Green
        $skipVenvRebuild = $true
    } else {
        Write-Log 'requirements.txt changed — rebuilding virtual environment.' -Color Blue
    }
}

if (-not $skipVenvRebuild) {
    if (Test-Path $venvDir) {
        Write-Log 'Removing existing .venv for rebuild...' -Color Blue
        Remove-Item -Recurse -Force $venvDir
        Write-Log 'Removed existing .venv.'
    }
}

Update-SessionPath

$knownPath = 'C:\Program Files\Python312\python.exe'
$pythonExe = $null
if (Test-Path $knownPath) {
    $pythonExe = $knownPath
    Write-Log "Found Python at known location: $pythonExe" -Color Green
} else {
    $pythonGcResult = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonGcResult) {
        $pythonExe = $pythonGcResult.Source
        Write-Log "Found Python on PATH: $pythonExe" -Color Green
    }
}

if ([string]::IsNullOrWhiteSpace($pythonExe)) {
    Write-Log 'Error: python.exe not found in known location or PATH. Cannot create virtual environment.' -Color Red
    Write-Log 'Checked locations:' -Color Red
    Write-Log "  - $knownPath (not found)" -Color Red
    Write-Log "Available Program Files:" -Color Red
    Get-ChildItem -Path 'C:\Program Files' -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*Python*' } | ForEach-Object { Write-Log "    - $_" -Color Red }
    exit 1
}

$versionOutput = & $pythonExe --version 2>&1
Write-Log "Python version check: $versionOutput" -Color Blue

if ($skipVenvRebuild) {
    Write-Log 'Skipping venv creation and pip install (requirements unchanged).' -Color Green
} else {
& $pythonExe -m venv $venvDir
if ($LASTEXITCODE -ne 0) {
    Write-Log "Error: failed to create virtual environment (exit $LASTEXITCODE)." -Color Red
    exit 1
}
Write-Log 'Virtual environment created.' -Color Green

$venvPython = Join-Path $venvDir 'Scripts\python.exe'
if (-not (Test-Path $venvPython)) {
    Write-Log "Error: venv python.exe not found at $venvPython" -Color Red
    Write-Log "venv contents: $(Get-ChildItem -Path $venvDir -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName | Out-String)" -Color Red
    exit 1
}

$venvPip = Join-Path $venvDir 'Scripts\pip.exe'
if (Test-Path $requirementsFile) {
    Write-Log 'Installing Python packages from requirements.txt...' -Color Blue
    Write-Log "Requirements file contents:" -Color Blue
    Get-Content $requirementsFile | ForEach-Object { Write-Log "  $_" -Color Blue }

    $venvPython = Join-Path $venvDir 'Scripts\python.exe'
    & $venvPython -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Warning: pip upgrade failed (exit $LASTEXITCODE). Continuing with current pip version." -Color Red
    }

    & $venvPip install -r $requirementsFile
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Error: pip install failed (exit $LASTEXITCODE)." -Color Red
        Write-Log "Running 'pip list' for diagnostics:" -Color Red
        & $venvPip list | ForEach-Object { Write-Log "  $_" -Color Red }
        exit 1
    }

    Write-Log 'Validating installed packages...' -Color Blue
    $requiredPackages = @('azure-identity', 'openai', 'python-dotenv', 'rich', 'colorama')
    $missingPackages = @()

    foreach ($pkg in $requiredPackages) {
        & $venvPip show $pkg >$null 2>&1
        if ($LASTEXITCODE -ne 0) {
            $missingPackages += $pkg
            Write-Log "  [MISSING] $pkg" -Color Red
        } else {
            Write-Log "  [OK] $pkg" -Color Green
        }
    }

    if ($missingPackages.Count -gt 0) {
        Write-Log "Error: required packages not installed: $($missingPackages -join ', ')" -Color Red
        Write-Log "Full pip list output:" -Color Red
        & $venvPip list | ForEach-Object { Write-Log "  $_" -Color Red }
        exit 1
    }

    Write-Log 'All required packages verified successfully.' -Color Green
} else {
    Write-Log 'Warning: requirements.txt not found, skipping pip install.' -Color Red
}
} # end else (venv rebuild) after a successful install so the next run can skip rebuild.
if (-not $skipVenvRebuild -and (Test-Path $requirementsFile)) {
    $newHash = (Get-FileHash $requirementsFile -Algorithm SHA256).Hash
    Set-Content -Path $venvHashFile -Value $newHash -Encoding ASCII
    Write-Log 'Stored new requirements hash for future idempotency checks.' -Color Green
}

$launchContent = @'
@echo off
title Enterprise AI Chat
cd /d C:\ChatApp
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -ExecutionPolicy Bypass -File "C:\ChatApp\first-run.ps1"
'@
Set-Content -Path "$appDir\launch-chat.bat" -Value $launchContent -Encoding ASCII
Write-Log 'Created launch-chat.bat.' -Color Green

$desktopPath = [Environment]::GetFolderPath('CommonDesktopDirectory')
$launchScriptPath = Join-Path $appDir 'launch-chat.bat'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut("$desktopPath\AI Chat.lnk")
$shortcut.TargetPath = $launchScriptPath
$shortcut.Arguments = ''
$shortcut.WorkingDirectory = $appDir
$shortcut.Description = 'Enterprise AI Chat Application'
$shortcut.Save()
Write-Log 'Created desktop shortcut.' -Color Green

if (Test-Path $windowsPowerShellPath) {
    Write-Log "Launcher will use Windows PowerShell at $windowsPowerShellPath." -Color Green
} else {
    Write-Log "Warning: expected Windows PowerShell not found at $windowsPowerShellPath." -Color Red
}

Write-Log 'Chat app setup complete' -Color Green
