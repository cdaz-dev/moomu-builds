# moomu, installed in one command (Windows, in PowerShell):  irm https://moomu.app/install.ps1 | iex
#   1. downloads the newest moomu for Windows from moomu's public releases (github.com/cdaz-dev/moomu-builds)
#   2. runs moomu's own installer quietly, just for you (no admin): %LOCALAPPDATA%\Programs\moomu, the Start menu, a
#      desktop icon, and an uninstaller in Settings > Apps
#   3. installs Claude Code with Anthropic's own installer if it isn't there yet (you sign in to it in moomu's first
#      run, in Claude Code's own window: moomu never sees your login)
#   4. installs a private copy of Node for moomu's browser if there's none (nothing system-wide)
#   5. downloads her voice (Chatterbox Turbo by Resemble AI, ~500 MB) and her ears (Moonshine, 136-257 MB), once, so
#      she can talk and listen as soon as she opens
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

    # her voice (Chatterbox Turbo, MIT, ~500 MB): downloaded now, once, so she can talk the moment she opens. Each file
    # checked against its fingerprint; anything that fails is fetched by moomu itself when it starts
    $voice = Join-Path $env:LOCALAPPDATA "moomu\moomu\voice\turbo"
    New-Item -ItemType Directory -Force (Join-Path $voice "onnx") | Out-Null
    $voiceFiles = @(
        @("tokenizer.json", 3562272, "3f04e34bea22f9144d1a19151154095bc9ce0430bf421304f5797e716288a906"),
        @("onnx/embed_tokens_q4.onnx", 2844, "fd6ba1d22902e8f539d3dd6d7c1c44b98ebb4c84ebbb5e47fcb826ddcf667561"),
        @("onnx/embed_tokens_q4.onnx_data", 37286384, "f54a51e234b509b64c3a03bb79e1149fba7e2eba6c2d9c222f18883379e1f5d8"),
        @("onnx/language_model_q4.onnx", 274572, "b39d03d3f8b943b9e60c6fce3fb41191dbc1df4589f913291db1e214eef669b1"),
        @("onnx/language_model_q4.onnx_data", 204456572, "2c029dc0acf48752473d8c74c72b5ceaaad76b9886fe106eaf2022142d5b5d5e"),
        @("onnx/conditional_decoder_q4.onnx", 2179022, "dccb7a6cea3472dc7f7d070eeb70ade18e6327fb4ec61a3d62cf211bfed90ea2"),
        @("onnx/conditional_decoder_q4.onnx_data", 246397384, "b5c5317e0b79a1a19dd3d5e2b2091ea06b15716716ab801a54eaeb906c6971ec")
    )
    $missing = @($voiceFiles | Where-Object { $f = Join-Path $voice $_[0]; -not ((Test-Path $f) -and (Get-Item $f).Length -eq $_[1]) })
    if ($missing.Count -gt 0) {
        Write-Host "downloading its voice and ears (about 650-750 MB, once)..."
        try {
            foreach ($v in $missing) {
                $f = Join-Path $voice $v[0]
                Invoke-WebRequest "https://huggingface.co/ResembleAI/chatterbox-turbo-ONNX/resolve/d21799bd0354adb85e348b8a0442a8405110a2cf/$($v[0])" -OutFile "$f.part" -UseBasicParsing
                if ((Get-FileHash "$f.part" -Algorithm SHA256).Hash.ToLower() -ne $v[2]) { Remove-Item "$f.part"; throw "checksum" }
                Move-Item "$f.part" $f -Force
            }
        } catch { Write-Host "(its voice will finish downloading when moomu opens)" }
    }

    # her ears (Moonshine, MIT): the medium model on a PC with 16 GB or more, the small one below (as the app picks)
    $ears = if ((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory -ge 15032385536) { "medium" } else { "small" }
    $earDir = Join-Path $env:LOCALAPPDATA "moomu\moomu\models\moonshine-$ears"
    New-Item -ItemType Directory -Force $earDir | Out-Null
    $earFiles = if ($ears -eq "medium") { @(
        @("adapter.ort", 3651296, "3f2a287def57cc094367a0eec3c4f5fc36a32ec420e86764b696920991b20281"),
        @("cross_kv.ort", 11643776, "642f6e21cd305be79342207c6f9e6b681d469d55bc48c72b27b84846fb71fd1e"),
        @("decoder_kv.ort", 146972408, "193bb366492b74fc4ad338c6778e8d8eb916aaa11b5aa264f9057f4db7759486"),
        @("encoder.ort", 94705376, "12915e76ebac7dd287c5ea63965d06103a53ba1ce242a4a34f318f3958c60c37"),
        @("frontend.model.ort", 28720, "95768855c70c8251eeecc05fedf69999da1b8ab16f605c9f457fd3354b0ad6b5"),
        @("frontend.weights.ort", 11889560, "5ac941f490cbe035b335b99a414cc393d62d4c6f9f2423495b286870d271d709"),
        @("streaming_config.json", 513, "28e83b7a28e91472692a035e0dae3116422ae43aeb2bef5ed822c44ce89b88af"),
        @("tokenizer.bin", 249974, "6884b35fd6377d4c4d32336a0bc152f36b64d1e45b6503683cdc238250a8472d")
    ) } else { @(
        @("adapter.ort", 2870368, "c665f742364febad597cc9ac1e0b341ffbee0e24a1466e2f3bde95e6e4771762"),
        @("cross_kv.ort", 5356536, "e2d3417144e9514055ebfefe8dcc4c0a55a55adcb8530435844c75c53e352bf6"),
        @("decoder_kv.ort", 81878600, "1a05465b1dd955858dfcbee039c0020fb5dd982b0f5094c34e61735d518d771b"),
        @("encoder.ort", 44148576, "2d4d973e91e8aca08c51e7e7efa28a46ab265b63d809d5294d18b86bcd85b993"),
        @("frontend.model.ort", 26944, "09b1210ae30dc5f0f3e45f0ebab914c254741323114f53fbbe5ae62cca35058f"),
        @("frontend.weights.ort", 7769464, "7ef97521bd4bad3928f5bb6808586f4fcc6e92bd5990394112eed7d4052ec338"),
        @("streaming_config.json", 512, "26f02b6afb22d60871a5efd85c3d38e569cc0ddb6c5eb6e93d3260152ae8a47a"),
        @("tokenizer.bin", 249974, "6884b35fd6377d4c4d32336a0bc152f36b64d1e45b6503683cdc238250a8472d")
    ) }
    try {
        foreach ($v in $earFiles) {
            $f = Join-Path $earDir $v[0]
            if ((Test-Path $f) -and (Get-Item $f).Length -eq $v[1]) { continue }
            Invoke-WebRequest "https://download.moonshine.ai/model/$ears-streaming-en/quantized_26_08_21/$($v[0])" -OutFile "$f.part" -UseBasicParsing
            if ((Get-FileHash "$f.part" -Algorithm SHA256).Hash.ToLower() -ne $v[2]) { Remove-Item "$f.part"; throw "checksum" }
            Move-Item "$f.part" $f -Force
        }
    } catch { Write-Host "(its ears will finish downloading when moomu opens)" }

    Write-Host "done. opening moomu"
    Start-Process $exe
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
