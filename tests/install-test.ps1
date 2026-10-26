# install.ps1 test (Windows). Runs the installer from this checkout with
# USERPROFILE and LOCALAPPDATA pointed at throwaway folders, so it never
# touches the real profile. Run it under both `pwsh` and `powershell`:
#   pwsh -File tests/install-test.ps1
#   powershell -ExecutionPolicy Bypass -File tests/install-test.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $repo 'install.ps1'
$shell = (Get-Process -Id $PID).Path
$T = Join-Path ([IO.Path]::GetTempPath()) ('bk-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $T | Out-Null
$script:fails = 0
$script:passes = 0

function Ok($msg) { Write-Output "ok:   $msg"; $script:passes++ }
function Fail($msg) { Write-Output "FAIL: $msg"; $script:fails++ }
function Check($cond, $msg) { if ($cond) { Ok $msg } else { Fail $msg } }

# Run the installer in a child shell. Mode 'file' runs it as a script;
# mode 'iex' pipes its text into Invoke-Expression, as `irm | iex` does,
# and then prints ALIVE to show the host shell was not closed.
function Run($homeDir, $localApp, [hashtable]$envs = @{}, $mode = 'file') {
    # Windows PowerShell 5.1 turns a child's stderr into an error record, and
    # 'Stop' would abort the test on the installer's own expected ERROR lines.
    $ErrorActionPreference = 'Continue'
    $saved = @{}
    $all = @{ USERPROFILE = $homeDir; LOCALAPPDATA = $localApp; BRAIN_KIT_SOURCE = $repo }
    foreach ($k in $envs.Keys) { $all[$k] = $envs[$k] }
    foreach ($k in $all.Keys) {
        $saved[$k] = [Environment]::GetEnvironmentVariable($k)
        [Environment]::SetEnvironmentVariable($k, $all[$k])
    }
    try {
        if ($mode -eq 'iex') {
            $cmd = "try { Get-Content -Raw -LiteralPath '$installer' | Invoke-Expression } catch { Write-Output ('ERROR: ' + `$_.Exception.Message) }; Write-Output ALIVE"
            $out = & $shell -NoProfile -NonInteractive -Command $cmd 2>&1 | Out-String
        } else {
            $out = & $shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installer 2>&1 | Out-String
        }
        return @{ Out = $out; Code = $LASTEXITCODE }
    } finally {
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
}

function Target($path) {
    $i = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if (-not $i) { return $null }
    $t = @($i.Target)[0]
    if ($t) { $t = $t -replace '^\\\\\?\\', '' -replace '^\\\?\?\\', '' }
    return $t
}

try {
    # ---- fresh install --------------------------------------------------------
    $H = Join-Path $T 'h1'; $L = Join-Path $H 'AppData\Local'
    New-Item -ItemType Directory -Force -Path (Join-Path $H '.cursor'), (Join-Path $H '.kiro'), $L | Out-Null
    $r = Run $H $L
    $skill = Join-Path $L 'brain-kit\skills\second-brain'
    Check ($r.Code -eq 0) "fresh install exits 0 ($($r.Out))"
    Check (Test-Path (Join-Path $skill 'SKILL.md')) 'skill copied'
    foreach ($d in '.claude', '.agents', '.cursor', '.kiro') {
        Check ((Target (Join-Path $H "$d\skills\second-brain")) -eq $skill) "junction in $d"
        Check (Test-Path (Join-Path $H "$d\skills\second-brain\SKILL.md")) "junction in $d resolves"
    }
    Check ($r.Out -match [regex]::Escape("cli:       $skill\scripts\brain")) 'prints the cli path'
    Check ($r.Out -match 'python:    \S') 'prints the python command'
    Check ($r.Out -match 'version:   second-brain') 'prints the version'
    Check ($r.Out -match '(?m)^done\.') 'prints done.'
    Check (-not (Get-ChildItem -LiteralPath $skill -Recurse -Force -Filter '__pycache__')) 'no __pycache__'
    $left = @(Get-ChildItem -LiteralPath (Join-Path $L 'brain-kit') -Force | Where-Object { $_.Name -notin 'skills', 'install.json' })
    $left += @(Get-ChildItem -LiteralPath (Join-Path $L 'brain-kit\skills') -Force | Where-Object Name -ne 'second-brain')
    Check ($left.Count -eq 0) 'no stage or lock left'

    # The installed CLI runs through the printed python command.
    $py = ([regex]::Match($r.Out, 'python:    (.+)')).Groups[1].Value.Trim() -split ' '
    $v = & $py[0] @($py | Select-Object -Skip 1) (Join-Path $skill 'scripts\brain') --version 2>&1 | Out-String
    Check ($v -match 'second-brain') "installed cli runs with '$($py -join ' ')'"

    $rc = Get-Content -Raw -LiteralPath (Join-Path $L 'brain-kit\install.json') | ConvertFrom-Json
    Check ($rc.method -eq 'install.ps1' -and $rc.source -eq "local:$repo" -and $rc.version -match '^\d+\.\d+\.\d+$') "writes the install receipt ($($rc | ConvertTo-Json -Compress))"
    Check ($r.Out -match [regex]::Escape("source:    local:$repo")) 'prints the source'

    # ---- re-run updates in place ---------------------------------------------
    Set-Content -LiteralPath (Join-Path $skill 'stale-file') -Value stale
    $r = Run $H $L
    Check ($r.Code -eq 0) 're-run exits 0'
    Check (-not (Test-Path (Join-Path $skill 'stale-file'))) 're-run replaces the old copy'
    Check (-not (Test-Path (Join-Path $skill 'second-brain'))) 're-run does not nest'
    Check (Test-Path (Join-Path $H '.claude\skills\second-brain\SKILL.md')) 'junction still resolves after re-run'

    # ---- moved LOCALAPPDATA repoints our own junctions ------------------------
    $L2 = Join-Path $T 'other-local'
    $r = Run $H $L2
    $skill2 = Join-Path $L2 'brain-kit\skills\second-brain'
    Check ((Target (Join-Path $H '.claude\skills\second-brain')) -eq $skill2) "junction repointed ($($r.Out))"
    Check (Test-Path $skill) 'repoint leaves the old copy in place'

    # ---- never replaces what it did not create --------------------------------
    $H = Join-Path $T 'h3'; $L = Join-Path $H 'AppData\Local'
    New-Item -ItemType Directory -Force -Path (Join-Path $H '.claude\skills\second-brain'), (Join-Path $H '.agents\skills'), (Join-Path $H '.cursor'), $L | Out-Null
    Set-Content -LiteralPath (Join-Path $H '.claude\skills\second-brain\SKILL.md') -Value mine
    $elsewhere = Join-Path $T 'elsewhere'; New-Item -ItemType Directory -Path $elsewhere | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $H '.agents\skills\second-brain') -Target $elsewhere | Out-Null
    Set-Content -LiteralPath (Join-Path $H '.cursor\skills') -Value 'not a dir'
    $r = Run $H $L
    Check ($r.Code -eq 0) 'install beside foreign files exits 0'
    Check ((Get-Content -LiteralPath (Join-Path $H '.claude\skills\second-brain\SKILL.md')) -eq 'mine') 'foreign folder left alone'
    Check ((Target (Join-Path $H '.agents\skills\second-brain')) -eq $elsewhere) 'foreign junction left alone'
    Check ($r.Out -match 'skipped:.*\.claude') 'reports the folder skip'
    Check ($r.Out -match 'skipped:.*\.cursor.*could not create') 'odd skills folder is skipped'
    Check ($r.Out -match '(?m)^done\.') 'odd skills folder does not abort'

    # ---- failures: error, no done., old install kept, shell stays open ---------
    $H = Join-Path $T 'h5'; $L = Join-Path $H 'AppData\Local'
    New-Item -ItemType Directory -Force -Path $L | Out-Null
    Run $H $L | Out-Null
    $skill = Join-Path $L 'brain-kit\skills\second-brain'
    function CheckFail($name, $r) {
        Check ($r.Out -match 'ERROR|Exception|could not|no skills|does not run|running') "$name reports an error"
        Check ($r.Out -notmatch '(?m)^done\.') "$name prints no done."
        Check (Test-Path (Join-Path $skill 'SKILL.md')) "$name keeps the old install"
    }
    CheckFail 'bad source' (Run $H $L @{ BRAIN_KIT_SOURCE = (Join-Path $T 'nothing') })
    $broken = Join-Path $T 'broken'
    Copy-Item -Recurse -LiteralPath (Join-Path $repo 'skills') -Destination (Join-Path $broken 'skills')
    Set-Content -LiteralPath (Join-Path $broken 'skills\second-brain\scripts\brain') -Value 'import sys; sys.exit(3)'
    CheckFail 'broken cli' (Run $H $L @{ BRAIN_KIT_SOURCE = $broken })
    $lock = Join-Path $L 'brain-kit\.lock'
    New-Item -ItemType Directory -Path $lock | Out-Null
    $r = Run $H $L
    CheckFail 'concurrent install' $r
    Check ($r.Out -match 'another brain-kit install is running') 'concurrent install explains itself'
    Check (Test-Path $lock) 'a failed run keeps the other run''s lock'
    Remove-Item -LiteralPath $lock

    $r = Run $H $L @{ BRAIN_KIT_SOURCE = (Join-Path $T 'nothing') } 'iex'
    Check ($r.Out -match 'ALIVE') 'a failure under iex does not close the shell'
    $r = Run $H $L @{} 'iex'
    Check ($r.Out -match '(?m)^done\.' -and $r.Out -match 'ALIVE') 'install under iex works'

    # ---- an interrupted swap is repaired by the next run -----------------------
    Move-Item -LiteralPath $skill -Destination "$skill.old"
    $r = Run $H $L
    Check ((Test-Path (Join-Path $skill 'SKILL.md')) -and -not (Test-Path "$skill.old")) 'half-done swap repaired'

    # ---- online: the real download installs the latest release ----------------
    # Set BRAIN_KIT_ONLINE_TEST=1 (CI does) to run it against GitHub.
    if ($env:BRAIN_KIT_ONLINE_TEST -eq '1') {
        $hdr = @{}; if ($env:GITHUB_TOKEN) { $hdr['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }
        $want = (Invoke-RestMethod -Uri 'https://api.github.com/repos/RobusGauli/brain-kit/releases/latest' -Headers $hdr -UseBasicParsing).tag_name
        $HO = Join-Path $T 'online'; $LO = Join-Path $HO 'AppData\Local'
        New-Item -ItemType Directory -Force -Path $LO | Out-Null
        $r = Run $HO $LO @{ BRAIN_KIT_SOURCE = '' }
        Check ($r.Out -match [regex]::Escape("source:    RobusGauli/brain-kit@$want") -and $r.Out -match '(?m)^done\.') "online install gets the latest release $want ($($r.Out))"
        $r = Run $HO $LO @{ BRAIN_KIT_SOURCE = ''; BRAIN_KIT_REF = 'v1.0.0' }
        Check ($r.Out -match 'source:    RobusGauli/brain-kit@v1\.0\.0' -and $r.Out -match 'version:   second-brain 1\.0\.0') 'online install honours BRAIN_KIT_REF'

        # brain update: install this checkout, then update it to a real release.
        # This swaps the folder the running CLI was started from.
        $HU = Join-Path $T 'online-update'; $LU = Join-Path $HU 'AppData\Local'
        New-Item -ItemType Directory -Force -Path $LU | Out-Null
        $r = Run $HU $LU
        $pyU = ([regex]::Match($r.Out, 'python:    (.+)')).Groups[1].Value.Trim() -split ' '
        $cliU = Join-Path $LU 'brain-kit\skills\second-brain\scripts\brain'
        $ErrorActionPreference = 'Continue'
        $savedLA = $env:LOCALAPPDATA; $env:LOCALAPPDATA = $LU
        try {
            $o = & $pyU[0] @($pyU | Select-Object -Skip 1) $cliU update --check 2>&1 | Out-String
            Check ($LASTEXITCODE -eq 0 -and $o -match [regex]::Escape("latest:    $want")) "update --check reports the latest release ($o)"
            $o = & $pyU[0] @($pyU | Select-Object -Skip 1) $cliU update --to v1.0.0 2>&1 | Out-String
            Check ($LASTEXITCODE -eq 0) "update --to exits 0 ($o)"
            $v = & $pyU[0] @($pyU | Select-Object -Skip 1) $cliU --version 2>&1 | Out-String
            Check ($v -match 'second-brain 1\.0\.0') "update --to installed that release in the same place ($v)"
            $rcU = Get-Content -Raw -LiteralPath (Join-Path $LU 'brain-kit\install.json') | ConvertFrom-Json
            Check ($rcU.source -eq 'RobusGauli/brain-kit@v1.0.0') "update --to rewrote the receipt ($($rcU | ConvertTo-Json -Compress))"
            Check (Test-Path (Join-Path $HU '.claude\skills\second-brain\SKILL.md')) 'junction still resolves after update'
        } finally { $env:LOCALAPPDATA = $savedLA; $ErrorActionPreference = 'Stop' }
    }

    # ---- the CLI writes LF and UTF-8 on Windows --------------------------------
    $ErrorActionPreference = 'Continue'   # native stderr, see Run
    $cli = Join-Path $skill 'scripts\brain'
    $py = ([regex]::Match($r.Out, 'python:    (.+)')).Groups[1].Value.Trim() -split ' '
    $V = Join-Path $T 'vaults'
    $env:XDG_CONFIG_HOME = Join-Path $T 'xdg-config'; $env:XDG_STATE_HOME = Join-Path $T 'xdg-state'
    & $py[0] @($py | Select-Object -Skip 1) $cli init --work-vault (Join-Path $V 'work') --personal-vault (Join-Path $V 'personal') --owner "In$([char]0xE9)s Pe$([char]0xF1)a" | Out-Null
    $out = & $py[0] @($py | Select-Object -Skip 1) $cli capture person --name "Zo$([char]0xEB) $([char]0xC5)ngstr$([char]0xF6)m" 2>&1 | Out-String
    Check ($LASTEXITCODE -eq 0) "capture with accented names works ($out)"
    $note = Get-ChildItem -LiteralPath (Join-Path $V 'work\People') -Filter '*.md' | Select-Object -First 1
    $bytes = [IO.File]::ReadAllBytes($note.FullName)
    Check (-not ($bytes -contains 13)) 'notes are written with LF, not CRLF'
} finally {
    Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ''
if ($script:fails -eq 0) {
    Write-Output "INSTALL TEST PASS ($($script:passes) assertions; $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion))"
    exit 0
}
Write-Output "INSTALL TEST FAIL ($($script:fails) failures, $($script:passes) passed)"
exit 1
