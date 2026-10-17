# Baobab AI film tools - installer for Windows 11.
#
# Run from PowerShell (it will be one line in the onboarding email):
#   irm https://raw.githubusercontent.com/BaobabStudios/artist-install/main/install.ps1 | iex
# The copy there is published from ai-film-pipeline/install/ (the source); don't edit it there.
#
# Installs what the tools need, gets the two artist repos and RV, and leaves the machine ready for
# "Set me up" in the Claude app. Safe to run again: a re-run repairs a half-finished install and
# never deletes anything. It never asks for or stores a password or key: GitHub sign-in happens in
# the browser.

# Continue, not Stop: in Windows PowerShell 5.1, Stop turns any native program's stderr into a fatal error.
# Every native call below checks $LASTEXITCODE instead.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$Org          = 'BaobabStudios'
$Repos        = @('AIFilmPipeline', 'NaraMediaHarness')
$OpenRVTag    = 'v3.1.0'
$OpenRVAsset  = 'OpenRV-3.1.0-windows-x64.zip'
$OpenRVInfo   = 'BUILD_INFO-windows-x64.txt'
$Base         = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Baobab'
$Venv         = Join-Path $Base '.venv'
$RVHome       = Join-Path $env:LOCALAPPDATA 'Baobab\OpenRV'
$ConfigDir    = Join-Path $HOME '.ai-film-pipeline'

function Say($msg)  { Write-Host "  $msg" }
function Step($msg) { Write-Host ""; Write-Host "== $msg" -ForegroundColor Cyan }
# throw, never exit: run through `irm | iex`, exit would close the artist's PowerShell window with the message.
function Stop-With($msg) { throw "STOP: $msg" }

function Refresh-Path {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$u;$m"
}

function Have($cmd) { return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Find-Python312 {
    foreach ($c in @("$env:LOCALAPPDATA\Programs\Python\Python312\python.exe", "$env:ProgramFiles\Python312\python.exe")) {
        if (Test-Path $c) { return $c }
    }
    if (Have 'py') { $p = (py -3.12 -c "import sys; print(sys.executable)" 2>$null); if ($LASTEXITCODE -eq 0 -and $p) { return $p.Trim() } }
    return $null
}

function Winget-Install($id, $label, $probe) {
    if ($probe -and (& $probe)) { Say "$label - already installed"; return }
    Say "$label - installing (a few minutes)..."
    winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
    Refresh-Path
    if ($probe -and -not (& $probe)) { Stop-With "$label didn't install. Run this installer again; if it fails twice, send the window's text to the help channel." }
}

function Install-BaobabTools {
Write-Host ""
Write-Host "Baobab AI film tools - installer" -ForegroundColor Green
Write-Host "This takes 10-20 minutes. Leave the window open until it says 'All done'."
Write-Host ""
Write-Host "Windows Security may pop up while this runs - sometimes hidden BEHIND this window - asking" -ForegroundColor Yellow
Write-Host "about git, Python, ffmpeg or RV. Each time, click Allow (or 'Allow on device'). If the installer" -ForegroundColor Yellow
Write-Host "seems stuck, look in the taskbar for a Windows Security window." -ForegroundColor Yellow

# ------------------------------------------------------------------ 1. the basics
Step "1/7  Checking this machine"
if ([Environment]::OSVersion.Version.Build -lt 22000) { Stop-With "this needs Windows 11." }
if (-not (Have 'winget')) { Stop-With "winget is missing. Install 'App Installer' from the Microsoft Store, then run this again." }
$free = (Get-PSDrive -Name ($Base.Substring(0,1))).Free / 1GB
if ($free -lt 15) { Stop-With ("only {0:N0} GB free; the tools need about 15 GB." -f $free) }
Say ("Windows 11, {0:N0} GB free" -f $free)

Step "2/7  Installing the tools the studio's tools run on"
Winget-Install 'Git.Git'              'git'              { Have 'git' }
Winget-Install 'Python.Python.3.12'   'Python 3.12'      { [bool](Find-Python312) }
Winget-Install 'Gyan.FFmpeg'          'ffmpeg'           { Have 'ffprobe' }
Winget-Install 'GitHub.cli'           'GitHub CLI'       { Have 'gh' }
Winget-Install 'Google.CloudSDK'      'Google Cloud SDK' { (Have 'gcloud') -or (Test-Path "$env:LOCALAPPDATA\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd") }

# ------------------------------------------------------------------ 2. GitHub
Step "3/7  Signing in to GitHub"
gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Say "A browser window will open. Sign in with the GitHub account you sent us, and enter the code shown here."
    gh auth login --web --git-protocol https --hostname github.com
    if ($LASTEXITCODE -ne 0) { Stop-With "GitHub sign-in didn't finish. Run this installer again." }
}
gh auth setup-git 2>$null | Out-Null
Say ("signed in as " + (gh api user --jq .login))

# ------------------------------------------------------------------ 3. the repos
Step "4/7  Getting the tools"
New-Item -ItemType Directory -Force -Path $Base | Out-Null
foreach ($r in $Repos) {
    $dest = Join-Path $Base $r
    if (Test-Path (Join-Path $dest '.git')) { Say "$r - already here (it updates itself when you start a session)"; continue }
    if (Test-Path $dest) { Stop-With "$dest exists but isn't a copy of the tools. Move it aside and run this again." }
    gh repo clone "$Org/$r" $dest -- -q
    if ($LASTEXITCODE -ne 0) { Stop-With "couldn't get $r. Have you accepted the GitHub invitation for it? Check your email, accept, and run this again." }
    Say "$r - done"
}
New-Item -ItemType Directory -Force -Path (Join-Path $Base 'projects') | Out-Null

# ------------------------------------------------------------------ 4. Python
Step "5/7  Setting up Python for the tools"
$py = Find-Python312
if (-not $py) { Stop-With "Python 3.12 isn't where it should be. Run this installer again." }
if (-not (Test-Path (Join-Path $Venv 'Scripts\python.exe'))) { & $py -m venv $Venv }
& (Join-Path $Venv 'Scripts\python.exe') -m pip install -q --upgrade pip
# Both repos' packages: the pipeline's (PyYAML) and the harness's (pillow, numpy, certifi).
foreach ($req in @('AIFilmPipeline\requirements.txt', 'NaraMediaHarness\requirements.txt')) {
    $f = Join-Path $Base $req
    if (-not (Test-Path $f)) { continue }
    & (Join-Path $Venv 'Scripts\python.exe') -m pip install -q -r $f
    if ($LASTEXITCODE -ne 0) { Stop-With "installing the Python packages failed. If Windows Security blocked Python, click Allow and run this again." }
}
# The tools call `python`; put this environment first so that is the one they get.
$scripts = Join-Path $Venv 'Scripts'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not (($userPath -split ';') -contains $scripts)) {
    [Environment]::SetEnvironmentVariable('Path', "$scripts;$userPath", 'User')
    Say "added the tools' Python to your PATH"
}
Refresh-Path
Say "Python ready"

# ------------------------------------------------------------------ 5. RV
Step "6/7  Installing RV (the review player)"
$rvExe = Get-ChildItem -Path $RVHome -Filter rv.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($rvExe) {
    Say "RV - already installed"
} else {
    $tmp = Join-Path $env:TEMP ("openrv-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    Say "downloading RV (about 450 MB)..."
    gh release download $OpenRVTag --repo "$Org/openrv-builds" --pattern $OpenRVAsset --pattern $OpenRVInfo --dir $tmp
    if ($LASTEXITCODE -ne 0) { Stop-With "couldn't download RV. Have you accepted the GitHub invitation for openrv-builds?" }
    $want = (Select-String -Path (Join-Path $tmp $OpenRVInfo) -Pattern 'SHA-256:\s*([0-9a-f]{64})').Matches[0].Groups[1].Value
    $got = (Get-FileHash -Algorithm SHA256 (Join-Path $tmp $OpenRVAsset)).Hash.ToLower()
    if ($got -ne $want) { Stop-With "the RV download is damaged (checksum mismatch). Run this again." }
    New-Item -ItemType Directory -Force -Path $RVHome | Out-Null
    Say "unpacking RV..."
    tar -xf (Join-Path $tmp $OpenRVAsset) -C $RVHome
    $rvExe = Get-ChildItem -Path $RVHome -Filter rv.exe -Recurse | Select-Object -First 1
    if (-not $rvExe) { Stop-With "RV unpacked but rv.exe is missing." }
    Say "RV - installed"
}

# ------------------------------------------------------------------ 6. config
# Where the tools are and where RV is, for the pipeline (pipeline/harness.py, pipeline/rv.py) and the
# harness (tools/rv_session.py). Only these two keys are set; anything else in the file is kept.
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
$cfg = Join-Path $ConfigDir 'config.yaml'
$keep = @()
if (Test-Path $cfg) { $keep = Get-Content $cfg | Where-Object { $_ -notmatch '^(harness_root|rv_exe):' } }
$lines = $keep + @("harness_root: '$((Join-Path $Base 'NaraMediaHarness'))'", "rv_exe: '$($rvExe.FullName)'")
[IO.File]::WriteAllLines($cfg, $lines, (New-Object Text.UTF8Encoding($false)))

# ------------------------------------------------------------------ 7. check
Step "7/7  Checking everything works"
$vpy = Join-Path $Venv 'Scripts\python.exe'
Push-Location (Join-Path $Base 'NaraMediaHarness'); & $vpy tools/preflight.py; Pop-Location
Push-Location (Join-Path $Base 'AIFilmPipeline'); & $vpy aifp.py harness; Pop-Location

$claude = (Test-Path "$env:LOCALAPPDATA\AnthropicClaude") -or [bool](Get-AppxPackage -Name '*Claude*' -ErrorAction SilentlyContinue)
if (-not $claude) {
    Say "The Claude desktop app isn't installed yet - opening the download page. Install it and sign in with your studio seat."
    Start-Process 'https://claude.ai/download'
}

Write-Host ""
Write-Host "All done." -ForegroundColor Green
Write-Host "Next: open the Claude app, go to the Code tab, open this folder:"
Write-Host "    $((Join-Path $Base 'AIFilmPipeline'))" -ForegroundColor Yellow
Write-Host "and say:  Set me up"
Write-Host "(If preflight above listed anything as missing, 'Set me up' walks you through it.)"
}

try {
    Install-BaobabTools
} catch {
    $m = "$($_.Exception.Message)"
    Write-Host ""
    if ($m.StartsWith('STOP: ')) { Write-Host ("Stopped: " + $m.Substring(6)) -ForegroundColor Red }
    else { Write-Host "Stopped by an unexpected error: $m" -ForegroundColor Red; Write-Host "Send this window's text to the help channel." }
}
