# moomu, installed in one command (Windows, in PowerShell):  irm https://moomu.app/install.ps1 | iex
#   1. downloads the newest moomu for Windows from moomu's public releases (github.com/cdaz-dev/moomu-builds)
#   2. runs moomu's own installer quietly, just for you (no admin): %LOCALAPPDATA%\Programs\moomu, the Start menu, a
#      desktop icon, and an uninstaller in Settings > Apps
#   3. installs Claude Code with Anthropic's own installer if it isn't there yet (you sign in to it in moomu's first
#      run, in Claude Code's own window: moomu never sees your login)
#   4. installs a private copy of Node for moomu's browser if there's none (nothing system-wide)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # (PowerShell 5's progress bar makes downloads many times slower)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$builds = "cdaz-dev/moomu-builds"
$tmp = Join-Path $env:TEMP ("moomu-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
    # the newest release with a Windows installer in it ($env:MOOMU_BASE: another place to download from)
    $url = $null
    if ($env:MOOMU_BASE) { $url = "$env:MOOMU_BASE/moomu-setup.exe" }
    else {
        $rels = Invoke-RestMethod "https://api.github.com/repos/$builds/releases?per_page=30" -Headers @{ "User-Agent" = "moomu-installer" }
        foreach ($r in @($rels)) {
            $a = @($r.assets) | Where-Object { $_.name -eq "moomu-setup.exe" } | Select-Object -First 1
            if ($a) { $url = $a.browser_download_url; Write-Host "downloading moomu (build $($r.tag_name.TrimStart('b')))..."; break }
        }
    }
    if (-not $url) { Write-Host "Couldn't reach moomu's downloads. Check your connection and try again."; return }   # (return, not exit: run with iex, exit closes the window)
    Invoke-WebRequest $url -OutFile "$tmp\moomu-setup.exe" -UseBasicParsing

    Write-Host "installing..."
    Get-Process moomu -ErrorAction SilentlyContinue | Stop-Process -Force
    $dest = Join-Path $env:LOCALAPPDATA "Programs\moomu"
    $exe = Join-Path $dest "moomu.exe"
    # moomu's installer: an uninstaller in Settings > Apps, the Start menu, a desktop icon
    Start-Process "$tmp\moomu-setup.exe" -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/TASKS="desktopicon"' -Wait
    # (an older install by this script left its own Start menu shortcut: the installer makes its own)
    Remove-Item (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\moomu.lnk") -ErrorAction SilentlyContinue

    # Claude Code: the native claude.exe, even when npm's is there. npm's claude.cmd runs through cmd.exe,
    # which mangles moomu's session arguments (every chat dies with "exit 255"). Both share the login in ~/.claude
    $claudeDir = Join-Path $env:USERPROFILE ".local\bin"
    $native = (Get-Command claude.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not (Test-Path (Join-Path $claudeDir "claude.exe")) -and -not $native) {
        Write-Host "installing Claude Code (Anthropic's own installer)..."
        Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
    }
    # (Claude Code's folder goes on your PATH when moomu opens: it keeps the PATH's own kind of value, which a script can't)

    # Node (moomu's browser runs on it): moomu's own copy if there's none (no admin, nothing system-wide)
    $nodeDir = Join-Path $env:LOCALAPPDATA "moomu\node"
    if (-not (Get-Command npx -ErrorAction SilentlyContinue) -and -not (Test-Path (Join-Path $nodeDir "npx.cmd"))) {
        Write-Host "installing Node for moomu's browser (its own copy)..."
        $sums = (Invoke-WebRequest https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt -UseBasicParsing).Content
        $file = ($sums -split "`n" | ForEach-Object { ($_ -split "\s+")[1] } | Where-Object { $_ -like "*win-x64.zip" } | Select-Object -First 1)
        if ($file) {
            Invoke-WebRequest "https://nodejs.org/dist/latest-v22.x/$file" -OutFile "$tmp\node.zip"
            Expand-Archive "$tmp\node.zip" -DestinationPath $tmp -Force
            if (Test-Path $nodeDir) { Remove-Item $nodeDir -Recurse -Force }
            New-Item -ItemType Directory -Force (Split-Path $nodeDir) | Out-Null
            Move-Item (Join-Path $tmp ($file -replace "\.zip$", "")) $nodeDir
        }
    }

    Write-Host "done. opening moomu"
    Start-Process $exe
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
