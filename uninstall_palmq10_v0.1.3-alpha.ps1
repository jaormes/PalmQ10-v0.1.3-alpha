# PalmQ10 v0.1.3-alpha uninstaller
# Conservative uninstall: removes PalmQ10 files/plugin/env, but does NOT uninstall QGIS, Ubuntu WSL, Miniconda, Go, or Apptainer by default.

$ErrorActionPreference = "Stop"

# -----------------------------
# CONFIG
# -----------------------------

$Docs = [Environment]::GetFolderPath("MyDocuments")
$PalmRoot = Join-Path $Docs "palmq10"
$DownloadDir = Join-Path $env:TEMP "palmq10_install_assets"

$QgisPluginDir = Join-Path $env:APPDATA "QGIS\QGIS3\profiles\default\python\plugins"
$PalmPluginDir = Join-Path $QgisPluginDir "palmq10_aoi"

$MinicondaDir = Join-Path $env:USERPROFILE "miniconda3"

# -----------------------------
# HELPERS
# -----------------------------

function Write-Step($msg) {
    Write-Host ""
    Write-Host "=== $msg ===" -ForegroundColor Cyan
}

function Confirm-Yes($Prompt, $DefaultNo = $true) {
    if ($DefaultNo) {
        $ans = Read-Host "$Prompt [y/N]"
        return ($ans -match "^[Yy]")
    } else {
        $ans = Read-Host "$Prompt [Y/n]"
        return ($ans -notmatch "^[Nn]")
    }
}

function Remove-PathIfExists($Path, $Label) {
    if (Test-Path $Path) {
        Write-Host "Removing ${Label}: $Path"
        Remove-Item -Recurse -Force $Path
    } else {
        Write-Host "Not found, skipping ${Label}: $Path"
    }
}

function Get-CondaExe {
    $cmd = Get-Command conda -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $local = Join-Path $MinicondaDir "Scripts\conda.exe"
    if (Test-Path $local) { return $local }

    return $null
}

function Remove-CondaEnv {
    Write-Step "Removing palmq10 conda environment"

    $conda = Get-CondaExe
    if (-not $conda) {
        Write-Host "Conda not found. Skipping conda environment removal."
        return
    }

    $envs = & $conda env list
    if ($envs -match "(^|\s)palmq10(\s|$)") {
        Write-Host "Removing conda environment: palmq10"
        & $conda env remove -n palmq10 -y
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Could not remove conda environment palmq10 automatically." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Conda environment palmq10 not found. Skipping."
    }
}

function Remove-WSLBuildTemp {
    Write-Step "Removing PalmQ10/Apptainer temporary build folders in WSL"

    try {
        $raw = & wsl.exe -l -q 2>$null
        $distros = @()
        foreach ($line in $raw) {
            $clean = ($line -replace "`0", "").Trim()
            if ($clean) { $distros += $clean }
        }
        $ubuntu = $distros | Where-Object { $_ -match "^Ubuntu" } | Select-Object -First 1

        if (-not $ubuntu) {
            Write-Host "Ubuntu WSL not detected. Skipping WSL temp cleanup."
            return
        }

        Write-Host "Using WSL distro: $ubuntu"
        $cmd = @'
set -e
rm -rf /tmp/apptainer || true
rm -rf "$HOME/palmq10_container_work" || true
rm -rf "$HOME/.cache/palmq10" || true
echo "WSL temporary PalmQ10 folders removed if present."
'@
        & wsl.exe -d $ubuntu bash -lc $cmd
    } catch {
        Write-Host "WARNING: WSL cleanup skipped: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Optional-Remove-Apptainer-Go {
    Write-Step "Optional WSL Go/Apptainer removal"

    if (-not (Confirm-Yes "Do you also want to remove Go and Apptainer from Ubuntu WSL? This may affect other projects." $true)) {
        Write-Host "Skipping Go/Apptainer removal."
        return
    }

    try {
        $raw = & wsl.exe -l -q 2>$null
        $distros = @()
        foreach ($line in $raw) {
            $clean = ($line -replace "`0", "").Trim()
            if ($clean) { $distros += $clean }
        }
        $ubuntu = $distros | Where-Object { $_ -match "^Ubuntu" } | Select-Object -First 1

        if (-not $ubuntu) {
            Write-Host "Ubuntu WSL not detected. Skipping Go/Apptainer removal."
            return
        }

        Write-Host "Ubuntu may ask for your sudo password."
        Write-Host "If prompted, enter your Ubuntu password, not your Windows password."

        $cmd = @'
set -e

echo "Removing Apptainer installed from source, if present..."
sudo rm -f /usr/local/bin/apptainer || true
sudo rm -rf /usr/local/libexec/apptainer || true
sudo rm -rf /usr/local/etc/apptainer || true
sudo rm -rf /usr/local/var/apptainer || true
sudo rm -rf /usr/local/share/man/man1/apptainer* || true
sudo rm -rf /usr/local/share/bash-completion/completions/apptainer || true
sudo rm -rf /usr/local/share/zsh/site-functions/_apptainer || true

if dpkg -s apptainer >/dev/null 2>&1; then
  echo "Removing apt-installed apptainer..."
  sudo apt remove -y apptainer || true
fi

if dpkg -s golang-go >/dev/null 2>&1; then
  echo "Removing apt-installed golang-go..."
  sudo apt remove -y golang-go || true
fi

sudo apt autoremove -y || true

echo "Go/Apptainer removal step finished."
'@
        & wsl.exe -d $ubuntu bash -lc $cmd
    } catch {
        Write-Host "WARNING: Optional Go/Apptainer removal failed or was skipped: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# -----------------------------
# MAIN
# -----------------------------

Write-Host "PalmQ10 v0.1.3-alpha uninstaller" -ForegroundColor Green
Write-Host "This removes PalmQ10-specific files only by default."
Write-Host "It will NOT remove QGIS, Ubuntu WSL, Miniconda base, Go, or Apptainer unless you explicitly choose optional removal."
Write-Host ""

if (-not (Confirm-Yes "Proceed with PalmQ10 uninstall?" $true)) {
    Write-Host "Uninstall cancelled."
    exit 0
}

Write-Step "Removing QGIS plugin"
Remove-PathIfExists $PalmPluginDir "PalmQ10 QGIS plugin"

Write-Step "Removing PalmQ10 local folder"
Remove-PathIfExists $PalmRoot "PalmQ10 root folder"

Write-Step "Removing installer temporary downloads"
Remove-PathIfExists $DownloadDir "PalmQ10 installer cache"

Remove-CondaEnv
Remove-WSLBuildTemp

Write-Step "Removing PALMQ10_ROOT user environment variable"
[System.Environment]::SetEnvironmentVariable("PALMQ10_ROOT", $null, "User")
Write-Host "PALMQ10_ROOT removed from user environment."

Optional-Remove-Apptainer-Go

Write-Step "Uninstall complete"
Write-Host "Removed:"
Write-Host "  - $PalmRoot"
Write-Host "  - $PalmPluginDir"
Write-Host "  - conda env palmq10, if found"
Write-Host "  - PALMQ10_ROOT user environment variable"
Write-Host ""
Write-Host "Not removed by default: QGIS, Ubuntu WSL, Miniconda base install."
Write-Host "Restart QGIS if it was open."
