# PalmQ10 v0.1.3-alpha installer
# Windows + QGIS + WSL2 Ubuntu alpha/private-beta installer
#
# This installer assumes the user has already:
#   1) Installed QGIS LTR and opened it once.
#   2) Installed Ubuntu from Microsoft Store, opened it once, created username/password,
#      and converted/verified it as WSL2.
#
# It does NOT install Ubuntu automatically. If Ubuntu/QGIS are missing, it pauses and
# asks the user to install them following the release-page instructions.

$ErrorActionPreference = "Stop"

# -----------------------------
# CONFIG
# -----------------------------

$GitHubOwner = "aramcue"
$GitHubRepo  = "palmq10-releases"
$ReleaseTag  = "v0.1.3-alpha"

# Asset destination rules:
#   dest = "DOWNLOAD" means temporary installer download folder.
#   otherwise dest is relative to C:\Users\<User>\Documents\palmq10
$Assets = @{
    "sourcecode_palmq10_v0.1.3-alpha.zip" = @{
        "dest" = "DOWNLOAD"
        "sha256" = "6a7447de687edb8c3095e4161fbd51a241c292f8db139ce2698a7054288ce56f"
    }

    "palmq10_aoi.zip" = @{
        "dest" = "DOWNLOAD"
        "sha256" = "fc20ce489ac08e1de81eb148d82ab728264e971000fa92447ff974e39cf983b7"
    }

    "palmq10.yml" = @{
        "dest" = "DOWNLOAD"
        "sha256" = "32825b5ea63a55c3d8b45e32498431d78e4b706be7c16035bf7efa9f80939a34"
    }

    "palm_latest.sif" = @{
        "dest" = "external\palm\palm_latest.sif"
        "sha256" = "81caaa55925934febbc849326deb1b0919618e6a1899a16ec8023fa5b3bdc068"
    }

    "geo4palm_latest.sif" = @{
        "dest" = "external\geo4palm\geo4palm_latest.sif"
        "sha256" = "0608a9fd2587d14a51159317ed80e1d41f25cfc5a54aeb668c7eab52b72802af"
    }

    "wrf4palm_latest.sif" = @{
        "dest" = "external\wrf4palm\wrf4palm_latest.sif"
        "sha256" = "f56a00a8694669f83f53af02326915f96faf809697e1926b92fb160f0fadfe7b"
    }

    "dtcenter_wps_wrf_latest_for_singularity.sif" = @{
        "dest" = "external\wrfwps\apptainer_images\dtcenter_wps_wrf_latest_for_singularity.sif"
        "sha256" = "75ba843a2313eea1fdeab3fe1f70557f7f59dd527664292c48b6a670bfd468c1"
    }

    "dtcenter_wps_wrf_4_1_0_for_singularity.sif" = @{
        "dest" = "external\wrfwps\apptainer_images\dtcenter_wps_wrf_4_1_0_for_singularity.sif"
        "sha256" = "1660ccaac3543aebceb722310fccf1d1c9a3f166ec57d46b47eb843a97cbcd4e"
    }

    "geog_high_res_mandatory.7z.001" = @{
        "dest" = "external\wps_geog\geog_high_res_mandatory.7z.001"
        "sha256" = "c14e132906950161b7b69063f20e954b6a15d97290436599ffb6b2bf8b4ee674"
    }

    "geog_high_res_mandatory.7z.002" = @{
        "dest" = "external\wps_geog\geog_high_res_mandatory.7z.002"
        "sha256" = "d570f607fb78fc1ffae8df8d1aa72672639b374cfe65fd92e058f1f3512b614b"
    }
}

$script:WslDistroName = $null
$script:ReleaseAssets = $null

$Docs = [Environment]::GetFolderPath("MyDocuments")
$PalmRoot = Join-Path $Docs "palmq10"
$DownloadDir = Join-Path $env:TEMP "palmq10_install_assets"

$QgisPluginDir = Join-Path $env:APPDATA "QGIS\QGIS3\profiles\default\python\plugins"
$PalmPluginDir = Join-Path $QgisPluginDir "palmq10_aoi"

$MinicondaDir = Join-Path $env:USERPROFILE "miniconda3"
$MinicondaExe = Join-Path $env:TEMP "Miniconda3-latest-Windows-x86_64.exe"
$MinicondaUrl = "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"

# -----------------------------
# UI HELPERS
# -----------------------------

function Write-Step($msg) {
    Write-Host ""
    Write-Host "=== $msg ===" -ForegroundColor Cyan
}

function Write-Warn($msg) {
    Write-Host $msg -ForegroundColor Yellow
}

function Write-Err($msg) {
    Write-Host $msg -ForegroundColor Red
}

function Get-FreeSpaceGB([string]$PathForDrive) {
    $root = [System.IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $PathForDrive -ErrorAction SilentlyContinue) -as [string])
    if (-not $root) {
        $root = [System.IO.Path]::GetPathRoot($PathForDrive)
    }
    $driveLetter = $root.Substring(0,1)
    $drive = Get-PSDrive -Name $driveLetter
    return [math]::Round($drive.Free / 1GB, 1)
}

function Check-DiskSpace {
    Write-Step "Checking available disk space"

    $freeGB = Get-FreeSpaceGB $Docs
    Write-Host "Free space on install drive: $freeGB GB"

    $minimumGB = 40
    $recommendedGB = 50

    if ($freeGB -lt $minimumGB) {
        Write-Err "Only $freeGB GB free. PalmQ10 installation needs at least $minimumGB GB free and $recommendedGB GB is recommended."
        Write-Host "Please free disk space before continuing."
        throw "Insufficient disk space for PalmQ10 installation."
    }

    if ($freeGB -lt $recommendedGB) {
        Write-Warn "Free space is below the recommended $recommendedGB GB. Installation may work, but future PALM outputs can be large."
        $ans = Read-Host "Continue anyway? Type Y to continue or N to stop"
        if ($ans -notmatch "^[Yy]") {
            throw "Installer stopped due to low free disk space."
        }
    }
}

function Remove-FileIfExists([string]$PathToRemove) {
    if (Test-Path $PathToRemove) {
        Remove-Item -Force $PathToRemove
        Write-Host "Removed installer/archive file: $PathToRemove"
    }
}

function Remove-DirectoryIfExists([string]$PathToRemove) {
    if (Test-Path $PathToRemove) {
        Remove-Item -Recurse -Force $PathToRemove
        Write-Host "Removed temporary directory: $PathToRemove"
    }
}

# -----------------------------
# GITHUB API DOWNLOAD HELPERS
# -----------------------------

function Require-Token {
    if (-not $env:GITHUB_TOKEN -or $env:GITHUB_TOKEN.Trim() -eq "") {
        Write-Host ""
        Write-Host "This is a private release. A GitHub fine-grained token is required."
        Write-Host "Recommended token permissions:"
        Write-Host "  Repository access: only aramcue/palmq10-releases"
        Write-Host "  Repository permissions: Contents = Read-only, Metadata = Read-only"
        Write-Host ""
        $token = Read-Host "Paste GitHub token for private release access"
        if (-not $token -or $token.Trim() -eq "") {
            throw "GitHub token is required for this private release."
        }
        $env:GITHUB_TOKEN = $token.Trim()
    }
}

function Get-GitHubHeaders([string]$Accept = "application/vnd.github+json") {
    $headers = @{
        "Accept" = $Accept
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent" = "PalmQ10-Installer"
    }

    if ($env:GITHUB_TOKEN) {
        $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN"
    }

    return $headers
}

function Get-ReleaseAssets {
    Write-Step "Checking GitHub release assets"

    $api = "https://api.github.com/repos/$GitHubOwner/$GitHubRepo/releases/tags/$ReleaseTag"

    try {
        $release = Invoke-RestMethod -Uri $api -Headers (Get-GitHubHeaders)
    } catch {
        Write-Err "Could not access GitHub release via API."
        Write-Host "Check that:"
        Write-Host "  1. The token is valid."
        Write-Host "  2. The token has access to $GitHubOwner/$GitHubRepo."
        Write-Host "  3. Fine-grained token permissions include Contents: Read-only and Metadata: Read-only."
        Write-Host "  4. The release tag exists: $ReleaseTag"
        throw
    }

    if (-not $release.assets -or $release.assets.Count -eq 0) {
        throw "No release assets found for tag $ReleaseTag."
    }

    Write-Host "Found $($release.assets.Count) release assets."
    return $release.assets
}

function Get-Sha256($Path) {
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()
}

function Download-Asset($Name, $OutPath) {
    if (-not $script:ReleaseAssets) {
        throw "Release assets have not been loaded. Call Get-ReleaseAssets first."
    }

    if (-not $Assets.ContainsKey($Name)) {
        throw "No installer config exists for asset: $Name"
    }

    $asset = $script:ReleaseAssets | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $asset) {
        $available = ($script:ReleaseAssets | ForEach-Object { $_.name }) -join ", "
        throw "Release asset not found: $Name`nAvailable assets: $available"
    }

    $expectedHash = $Assets[$Name]["sha256"]

    New-Item -ItemType Directory -Force -Path (Split-Path $OutPath) | Out-Null

    if (Test-Path $OutPath) {
        $actualHash = Get-Sha256 $OutPath
        if ($actualHash -eq $expectedHash) {
            Write-Host "Already exists and checksum OK, skipping: $OutPath"
            return
        }

        Write-Warn "Existing file checksum mismatch. Re-downloading: $OutPath"
        Remove-Item -Force $OutPath
    }

    Write-Host "Downloading $Name..."
    Write-Host "  -> $OutPath"

    try {
        Invoke-WebRequest `
            -Uri $asset.url `
            -OutFile $OutPath `
            -Headers (Get-GitHubHeaders "application/octet-stream")
    } catch {
        Write-Err "Download failed for $Name."
        Write-Host "This usually means token access failed or the asset name changed."
        throw
    }

    $actualAfter = Get-Sha256 $OutPath
    if ($actualAfter -ne $expectedHash) {
        Remove-Item -Force $OutPath -ErrorAction SilentlyContinue
        throw "Checksum mismatch for $Name`nExpected: $expectedHash`nActual:   $actualAfter"
    }

    Write-Host "Checksum OK: $Name"
}

# -----------------------------
# PREREQUISITE CHECKS
# -----------------------------

function Wait-For-QGIS {
    Write-Step "Checking QGIS profile folder"

    while (-not (Test-Path $QgisPluginDir)) {
        Write-Warn "QGIS profile folder not found:"
        Write-Host "  $QgisPluginDir"
        Write-Host ""
        Write-Host "Please install QGIS LTR from https://qgis.org/download/ and open QGIS once."
        Write-Host "Then return here and recheck."
        $ans = Read-Host "Type Y to recheck or N to stop"
        if ($ans -notmatch "^[Yy]") {
            throw "QGIS not detected. Installer stopped."
        }
    }

    Write-Host "QGIS profile found: $QgisPluginDir"
}

function Wait-For-WSLUbuntu {
    Write-Step "Checking Ubuntu on WSL2"

    while ($true) {
        $distros = @()

        try {
            $raw = & wsl.exe -l -q 2>$null
            foreach ($line in $raw) {
                $clean = ($line -replace "`0", "").Trim()
                if ($clean) { $distros += $clean }
            }
        } catch {
            # fall through to user prompt
        }

        $ubuntu = $distros | Where-Object { $_ -match "^Ubuntu" } | Select-Object -First 1

        if ($ubuntu) {
            $script:WslDistroName = $ubuntu
            Write-Host "Ubuntu WSL detected: $script:WslDistroName"

            $verboseRaw = & wsl.exe -l -v
            $verboseClean = (($verboseRaw | ForEach-Object { ($_ -replace "`0", "").TrimEnd() }) -join "`n")

            Write-Host ""
            Write-Host $verboseClean
            Write-Host ""

            $escapedName = [regex]::Escape($script:WslDistroName)
            $lineForUbuntu = ($verboseClean -split "`n") |
                Where-Object { $_ -match "^\*?\s*$escapedName\s+" } |
                Select-Object -First 1

            if ($lineForUbuntu -match "\s1\s*$") {
                Write-Err "Ubuntu is installed as WSL1, but PalmQ10 requires WSL2."
                Write-Host ""
                Write-Host "Please run these in PowerShell as Administrator:"
                Write-Host "  wsl --set-default-version 2"
                Write-Host "  wsl --set-version $script:WslDistroName 2"
                Write-Host ""
                Write-Host "Then verify:"
                Write-Host "  wsl -l -v"
                Write-Host "Expected: Ubuntu ... VERSION 2"
                throw "WSL1 detected. Convert Ubuntu to WSL2 before running installer."
            }

            if ($lineForUbuntu -match "\s2\s*$") {
                Write-Host "Ubuntu is using WSL2."
                return
            }

            Write-Warn "Could not confirm WSL version from the output above."
            Write-Host "Please verify manually that Ubuntu shows VERSION 2 with:"
            Write-Host "  wsl -l -v"
            $ans = Read-Host "Type Y to continue anyway, or N to stop"
            if ($ans -match "^[Yy]") { return }
            throw "Could not confirm WSL2."
        }

        Write-Warn "Ubuntu for WSL was not detected."
        Write-Host ""
        Write-Host "Please follow the release-page instructions:"
        Write-Host "  1. Install Ubuntu from Microsoft Store."
        Write-Host "  2. Open Ubuntu once and create your Linux username/password."
        Write-Host "  3. In PowerShell as Administrator, run:"
        Write-Host "       wsl --set-default-version 2"
        Write-Host "       wsl --set-version Ubuntu 2"
        Write-Host "  4. Confirm:"
        Write-Host "       wsl -l -v"
        Write-Host "     Expected: Ubuntu ... VERSION 2"
        Write-Host ""
        $ans = Read-Host "After doing that, type Y to recheck or N to stop"
        if ($ans -notmatch "^[Yy]") {
            throw "WSL Ubuntu not detected. Installer stopped."
        }
    }
}

# -----------------------------
# LOCAL WINDOWS INSTALL HELPERS
# -----------------------------

function Ensure-Miniconda {
    Write-Step "Checking Miniconda"

    $condaCmd = Get-Command conda -ErrorAction SilentlyContinue
    if ($condaCmd) {
        Write-Host "Conda found: $($condaCmd.Source)"
        return
    }

    $localConda = Join-Path $MinicondaDir "Scripts\conda.exe"
    if (Test-Path $localConda) {
        Write-Host "Miniconda found at: $MinicondaDir"
        return
    }

    Write-Host "Miniconda not found. Installing per-user Miniconda..."
    Invoke-WebRequest -Uri $MinicondaUrl -OutFile $MinicondaExe

    Start-Process -FilePath $MinicondaExe -ArgumentList "/InstallationType=JustMe /RegisterPython=0 /S /D=$MinicondaDir" -Wait

    if (-not (Test-Path $localConda)) {
        throw "Miniconda installation did not produce conda.exe."
    }

    Write-Host "Miniconda installed at: $MinicondaDir"
}

function Get-CondaExe {
    $cmd = Get-Command conda -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $local = Join-Path $MinicondaDir "Scripts\conda.exe"
    if (Test-Path $local) { return $local }

    throw "conda.exe not found."
}

function Ensure-CondaEnv($YmlPath) {
    Write-Step "Creating/updating palmq10 conda environment"

    $conda = Get-CondaExe

    # Use a temporary installer-only .condarc so PalmQ10 env creation uses
    # conda-forge with strict priority WITHOUT modifying the user's global conda config.
    $tempCondarc = Join-Path $env:TEMP "palmq10_condarc.yml"

@"
channels:
  - conda-forge
channel_priority: strict
"@ | Set-Content -Path $tempCondarc -Encoding ASCII

    $oldCondarc = $env:CONDARC
    $env:CONDARC = $tempCondarc

    try {
        $envs = & $conda env list

        if ($envs -match "palmq10") {
            Write-Host "Environment palmq10 exists. Updating using temporary conda-forge-only config..."
            & $conda env update -n palmq10 -f $YmlPath --prune
        } else {
            Write-Host "Creating environment palmq10 using temporary conda-forge-only config..."
            & $conda env create -f $YmlPath
        }

        if ($LASTEXITCODE -ne 0) {
            throw "Conda environment setup failed."
        }
    }
    finally {
        if ($oldCondarc) {
            $env:CONDARC = $oldCondarc
        } else {
            Remove-Item Env:\CONDARC -ErrorAction SilentlyContinue
        }

        Remove-Item $tempCondarc -Force -ErrorAction SilentlyContinue
    }
}


function Ensure-7Zip {
    Write-Step "Checking 7-Zip"

    $seven = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($seven) {
        Write-Host "7-Zip found: $($seven.Source)"
        return $seven.Source
    }

    foreach ($p in @("C:\Program Files\7-Zip\7z.exe", "C:\Program Files (x86)\7-Zip\7z.exe")) {
        if (Test-Path $p) {
            Write-Host "7-Zip found: $p"
            return $p
        }
    }

    Write-Warn "7-Zip not found."
    Write-Host "Please install 7-Zip from https://www.7-zip.org/"
    while ($true) {
        $ans = Read-Host "Type Y after installing 7-Zip, or N to stop"
        if ($ans -match "^[Nn]") { throw "7-Zip required for WPS geog extraction." }
        if ($ans -match "^[Yy]") { return (Ensure-7Zip) }
    }
}

function Extract-ZipClean($ZipPath, $DestPath) {
    if (Test-Path $DestPath) {
        Write-Host "Removing existing folder: $DestPath"
        Remove-Item -Recurse -Force $DestPath
    }

    New-Item -ItemType Directory -Force -Path (Split-Path $DestPath) | Out-Null

    $tmpExtract = Join-Path $env:TEMP ("palmq10_extract_" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Force -Path $tmpExtract | Out-Null

    Expand-Archive -Path $ZipPath -DestinationPath $tmpExtract -Force

    $children = @(Get-ChildItem $tmpExtract)
    if ($children.Count -eq 1 -and $children[0].PSIsContainer) {
        Move-Item -Path $children[0].FullName -Destination $DestPath
    } else {
        New-Item -ItemType Directory -Force -Path $DestPath | Out-Null
        Get-ChildItem $tmpExtract | Move-Item -Destination $DestPath
    }

    Remove-Item -Recurse -Force $tmpExtract
}

# -----------------------------
# WSL DEPS
# -----------------------------

function Test-WSLCommand([string]$CommandName) {
    if (-not $script:WslDistroName) {
        throw "No Ubuntu WSL distro selected."
    }

    & wsl.exe -d $script:WslDistroName bash -lc "command -v $CommandName >/dev/null 2>&1"
    return ($LASTEXITCODE -eq 0)
}

function Get-WSLCommandOutput([string]$Command) {
    if (-not $script:WslDistroName) {
        throw "No Ubuntu WSL distro selected."
    }

    $out = & wsl.exe -d $script:WslDistroName bash -lc "$Command" 2>&1
    return ($out -join "`n")
}

function Verify-WSLRuntime {
    Write-Step "Verifying WSL runtime"

    if (-not (Test-WSLCommand "go")) {
        throw "Go is not available inside WSL Ubuntu after dependency installation."
    }

    if (-not (Test-WSLCommand "apptainer")) {
        throw "Apptainer is not available inside WSL Ubuntu after dependency installation."
    }

    $goVersion = Get-WSLCommandOutput "go version"
    $apptainerVersion = Get-WSLCommandOutput "apptainer --version"

    Write-Host "Go detected:        $goVersion"
    Write-Host "Apptainer detected: $apptainerVersion"
}


function Convert-WindowsPathToWslPath($WindowsPath) {
    $full = [System.IO.Path]::GetFullPath($WindowsPath)

    if ($full -notmatch "^[A-Za-z]:\\") {
        throw "Cannot convert non-drive Windows path to WSL path: $full"
    }

    $drive = $full.Substring(0, 1).ToLower()
    $rest = $full.Substring(3).Replace("\", "/")
    return "/mnt/$drive/$rest"
}

function Install-WSLDeps {
    Write-Step "Installing WSL-side dependencies (Go + Apptainer)"

    if (-not $script:WslDistroName) {
        throw "No Ubuntu WSL distro selected."
    }

    Write-Host "This step prepares the Linux-side runtime inside WSL Ubuntu."
    Write-Host "Ubuntu may ask for your sudo password."
    Write-Host "If prompted, enter your Ubuntu password, not your Windows password."
    Write-Host ""

    $bashScriptWin = Join-Path $env:TEMP "palmq10_install_wsl_deps.sh"

@'
#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[PalmQ10 WSL] $1"
}

log "Checking existing WSL tools..."

# The HPC credential vault (internal/clusters/credential_vault.py) imports `cryptography`
# inside WSL's python3. Both shipped cluster profiles default to auth_mode: key_vault, so
# without this a first cluster job fails on an import error. Done before the Apptainer
# branching below because that section has several early exits.
log "Checking Python cryptography module (required by the HPC credential vault)..."
if python3 -c "import cryptography" >/dev/null 2>&1; then
  log "cryptography already available."
else
  log "cryptography not found. Installing..."
  sudo apt update
  sudo apt install -y python3-cryptography || python3 -m pip install --user cryptography
  if python3 -c "import cryptography" >/dev/null 2>&1; then
    log "cryptography installed."
  else
    log "WARNING: could not install cryptography."
    log "         Local runs are unaffected; HPC cluster jobs will fail until you run:"
    log "         python3 -m pip install --user cryptography"
  fi
fi

if command -v apptainer >/dev/null 2>&1 && command -v ssh >/dev/null 2>&1 && command -v rsync >/dev/null 2>&1; then
  log "Apptainer already available: $(apptainer --version)"
  if command -v go >/dev/null 2>&1; then
    log "Go already available: $(go version)"
  else
    log "Go not found, but Apptainer already exists. Go is only required if Apptainer must be built from source."
  fi
  log "WSL runtime already ready."
  exit 0
fi

log "Apptainer not found."
log "Updating apt package lists..."
sudo apt update
log "Installing WSL SSH/rsync runtime dependencies..."
sudo apt install -y openssh-client rsync

log "Trying apt install apptainer first..."
if sudo apt install -y apptainer; then
  if command -v apptainer >/dev/null 2>&1; then
    log "Apptainer installed via apt: $(apptainer --version)"
    log "WSL runtime ready."
    exit 0
  fi
fi

log "apt install apptainer did not work on this Ubuntu/WSL setup."
log "Proceeding to install Go and build Apptainer from source."

log "Installing base build/runtime dependencies..."
sudo apt install -y \
  build-essential wget curl git openssh-client rsync \
  squashfs-tools squashfuse fuse2fs gocryptfs fuse3 \
  cryptsetup uidmap pkg-config libseccomp-dev libglib2.0-dev

if command -v go >/dev/null 2>&1; then
  log "Go already available: $(go version)"
else
  log "Installing Go via apt..."
  sudo apt install -y golang-go
fi

if ! command -v go >/dev/null 2>&1; then
  echo "[PalmQ10 WSL] ERROR: Go installation failed; cannot build Apptainer."
  exit 10
fi

log "Go ready: $(go version)"

cd /tmp
rm -rf apptainer

log "Cloning Apptainer source..."
git clone https://github.com/apptainer/apptainer.git
cd apptainer

log "Checking out stable release v1.2.5..."
git checkout v1.2.5

log "Configuring Apptainer build..."
./mconfig

log "Compiling Apptainer. This may take several minutes..."
make -C builddir

log "Installing Apptainer into WSL Ubuntu..."
sudo make -C builddir install

if command -v apptainer >/dev/null 2>&1; then
  log "Apptainer successfully built and installed: $(apptainer --version)"
else
  echo "[PalmQ10 WSL] ERROR: Apptainer installation failed."
  exit 20
fi

log "Final runtime check:"
if command -v go >/dev/null 2>&1; then
  go version
fi
apptainer --version
log "Go + Apptainer setup completed successfully."
'@ | Set-Content -Path $bashScriptWin -Encoding ASCII

    $bashScriptWsl = Convert-WindowsPathToWslPath $bashScriptWin
    Write-Host "WSL dependency script: $bashScriptWsl"

    & wsl.exe -d $script:WslDistroName bash -lc "chmod +x '$bashScriptWsl' && '$bashScriptWsl'"

    if ($LASTEXITCODE -ne 0) {
        throw "WSL dependency installation failed. Apptainer/Go were not prepared correctly."
    }

    Remove-Item $bashScriptWin -Force -ErrorAction SilentlyContinue
}

# -----------------------------
# MAIN
# -----------------------------

Write-Host "PalmQ10 v0.1.3-alpha installer" -ForegroundColor Green
Write-Host "Install root: $PalmRoot"

New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null

Check-DiskSpace

# Prerequisites first. Token is requested only after local prerequisites pass.
Wait-For-QGIS
Wait-For-WSLUbuntu

Require-Token
$script:ReleaseAssets = Get-ReleaseAssets

Write-Step "Downloading PalmQ10 code and environment"

$palmZip   = Join-Path $DownloadDir "sourcecode_palmq10_v0.1.3-alpha.zip"
$pluginZip = Join-Path $DownloadDir "palmq10_aoi.zip"
$ymlPath   = Join-Path $DownloadDir "palmq10.yml"

Download-Asset "sourcecode_palmq10_v0.1.3-alpha.zip" $palmZip
Download-Asset "palmq10_aoi.zip" $pluginZip
Download-Asset "palmq10.yml" $ymlPath

# Extract-ZipClean deletes $PalmRoot wholesale before extracting, which would destroy the
# user's projects and their filled-in access keys. Move just those two aside and put them
# back afterwards; everything else (code, containers, geographic data) is deliberately
# replaced so no stale artefact survives an upgrade. Both locations are under Documents, so
# these are same-volume moves (instant, no extra disk needed) rather than copies.
$PreserveDir = $null
if (Test-Path $PalmRoot) {
    Write-Step "Preserving your projects and access keys"
    $PreserveDir = Join-Path $Docs ("palmq10_preserved_" + [guid]::NewGuid().ToString("N").Substring(0,8))
    New-Item -ItemType Directory -Force -Path $PreserveDir | Out-Null

    $jobsSrc = Join-Path $PalmRoot "jobs"
    if (Test-Path $jobsSrc) {
        Write-Host "  keeping your jobs\ folder (projects and results)"
        Move-Item -LiteralPath $jobsSrc -Destination (Join-Path $PreserveDir "jobs") -Force
    }

    $keysSrc = Join-Path $PalmRoot "documentation\ACCESS_KEYS_EDIT.txt"
    if (Test-Path $keysSrc) {
        Write-Host "  keeping your filled-in ACCESS_KEYS_EDIT.txt"
        Move-Item -LiteralPath $keysSrc -Destination (Join-Path $PreserveDir "ACCESS_KEYS_EDIT.txt") -Force
    }
}

Write-Step "Extracting PalmQ10 local folder"
Extract-ZipClean $palmZip $PalmRoot
Remove-FileIfExists $palmZip

if ($PreserveDir) {
    Write-Step "Restoring your data"

    $jobsSaved = Join-Path $PreserveDir "jobs"
    if (Test-Path $jobsSaved) {
        $jobsDst = Join-Path $PalmRoot "jobs"
        if (Test-Path $jobsDst) { Remove-Item -Recurse -Force $jobsDst }
        Move-Item -LiteralPath $jobsSaved -Destination $jobsDst -Force
        Write-Host "  restored jobs\ (your projects and results are intact)"
    }

    $keysSaved = Join-Path $PreserveDir "ACCESS_KEYS_EDIT.txt"
    if (Test-Path $keysSaved) {
        $keysDst = Join-Path $PalmRoot "documentation\ACCESS_KEYS_EDIT.txt"
        New-Item -ItemType Directory -Force -Path (Split-Path $keysDst) | Out-Null
        Move-Item -LiteralPath $keysSaved -Destination $keysDst -Force
        Write-Host "  restored ACCESS_KEYS_EDIT.txt (your credentials were not lost)"
    }

    Remove-DirectoryIfExists $PreserveDir
}

Write-Step "Installing QGIS plugin"
Extract-ZipClean $pluginZip $PalmPluginDir
Remove-FileIfExists $pluginZip

Ensure-Miniconda
Ensure-CondaEnv $ymlPath
Remove-FileIfExists $ymlPath

Install-WSLDeps

Write-Step "Downloading Apptainer/Singularity images and WPS geographic parts"

foreach ($name in $Assets.Keys) {
    $destRel = $Assets[$name]["dest"]
    if ($destRel -eq "DOWNLOAD") { continue }

    $destAbs = Join-Path $PalmRoot $destRel
    Download-Asset $name $destAbs
}

Write-Step "Extracting WPS geographic data"

$wpsDir = Join-Path $PalmRoot "external\wps_geog"
# Discover every downloaded volume rather than assuming exactly two, so that a future
# geog rebuild needing .003+ extracts and cleans up correctly without editing this script.
$geogParts = @(Get-ChildItem -Path $wpsDir -Filter "geog_high_res_mandatory.7z.*" -File -ErrorAction SilentlyContinue | Sort-Object Name)
$geogPart1 = Join-Path $wpsDir "geog_high_res_mandatory.7z.001"
$geogExtractedDir = Join-Path $wpsDir "geog_high_res_mandatory"

if ($geogParts.Count -eq 0) {
    throw "No WPS geog archive parts found in: $wpsDir"
}
if (-not (Test-Path $geogPart1)) {
    throw "Missing first WPS geog archive part: $geogPart1"
}

Write-Host "Found $($geogParts.Count) WPS geog archive part(s)."

if (Test-Path $geogExtractedDir) {
    Write-Warn "Existing extracted WPS geog folder found. Removing before clean extraction:"
    Write-Host "  $geogExtractedDir"
    Remove-Item -Recurse -Force $geogExtractedDir
}

$sevenZip = Ensure-7Zip
& $sevenZip x $geogPart1 "-o$wpsDir" -y

if ($LASTEXITCODE -ne 0) {
    throw "7-Zip extraction failed. Free disk space and rerun the installer."
}

# Verify that extraction created the expected geog folder and at least one known dataset.
if (-not (Test-Path $geogExtractedDir)) {
    throw "WPS geog extraction finished but expected folder was not found: $geogExtractedDir"
}

$knownGeogChild = Join-Path $geogExtractedDir "WPS_GEOG"
if (-not (Test-Path $knownGeogChild)) {
    Write-Warn "Expected WPS_GEOG marker folder was not found. Checking for other known geog folders..."
    $fallbackChild = Join-Path $geogExtractedDir "modis_landuse_20class_30s_with_lakes"
    if (-not (Test-Path $fallbackChild)) {
        throw "WPS geog extraction did not produce expected contents in: $geogExtractedDir"
    }
}

Write-Host "WPS geographic data extracted successfully."

# The split archives are no longer needed after a verified extraction.
foreach ($part in $geogParts) {
    Remove-FileIfExists $part.FullName
}

# Clean temporary download directory if empty/leftover.
Remove-DirectoryIfExists $DownloadDir

Write-Step "Setting PALMQ10_ROOT user environment variable"

[System.Environment]::SetEnvironmentVariable("PALMQ10_ROOT", $PalmRoot, "User")
Write-Host "PALMQ10_ROOT = $PalmRoot"

Write-Step "Installation complete"

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Restart QGIS."
Write-Host "2. Enable the PalmQ10 plugin if needed."
Write-Host "3. Confirm the plugin root path points to:"
Write-Host "   $PalmRoot"
Write-Host ""
Write-Host "Installed plugin:"
Write-Host "   $PalmPluginDir"
Write-Host ""
Write-Host "Installed conda env:"
Write-Host "   palmq10"
