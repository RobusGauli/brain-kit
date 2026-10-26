# brain-kit installer for Windows: puts the second-brain skill where coding
# agents find it.
#
#   irm https://raw.githubusercontent.com/RobusGauli/brain-kit/main/install.ps1 | iex
#
# What it does (safe to re-run; re-running updates to the latest release):
#   1. finds a working Python 3.9+ (py -3, python3 or python; not the Store stub)
#   2. downloads the latest GitHub release (not the main branch) and keeps
#      skills\second-brain\ under %LOCALAPPDATA%\brain-kit\, with a receipt in
#      install.json (version, ref, date)
#   3. links that folder into ~\.claude\skills\ and ~\.agents\skills\
#      (and ~\.cursor\skills\, ~\.kiro\skills\ when those tools are present),
#      using directory junctions, which need no admin rights
#
# It never touches your vaults or your config, never replaces a file or link
# it did not create, and does not change PATH. It does not run `brain init`.
#
# Output contract (agents read it): `installed:`, then `linked:` / `skipped:`
# lines, then `python:`, `cli:`, `version:`, `source:` and a final `done.`.
# No `done.` line means the install did not finish.
#
# Pin a version: $env:BRAIN_KIT_REF = 'v1.0.1' (a tag, branch or commit;
# default: the latest release).
#
# Overrides: $env:BRAIN_KIT_REF (see above),
#            $env:BRAIN_KIT_SOURCE (a local checkout to install from, for testing).
#
# Errors throw instead of calling `exit`, because `irm | iex` runs inside the
# user's own shell and `exit` would close it. The body is one function called
# on the last line.

function Install-BrainKit {
    $ErrorActionPreference = 'Stop'
    Set-StrictMode -Version 2.0

    $repo = 'RobusGauli/brain-kit'
    $ref = $env:BRAIN_KIT_REF   # empty: the latest release, resolved below
    if (-not $env:USERPROFILE -or -not $env:LOCALAPPDATA) {
        throw 'USERPROFILE or LOCALAPPDATA is not set.'
    }
    $home_ = $env:USERPROFILE
    $data = Join-Path $env:LOCALAPPDATA 'brain-kit'
    $skills = Join-Path $data 'skills'
    $skill = Join-Path $skills 'second-brain'

    # 1. Python 3.9+
    $py = Find-Python
    if (-not $py) {
        throw 'no working Python 3.9 or newer found. Install it from python.org (tick "Add python.exe to PATH"), then run this again.'
    }

    # One install at a time. Stage beside the target so the swap is a rename.
    New-Item -ItemType Directory -Force -Path $skills | Out-Null
    $lock = Join-Path $data '.lock'
    try { New-Item -ItemType Directory -Path $lock | Out-Null }
    catch { throw "another brain-kit install is running. If none is, delete $lock and run this again." }
    $stage = Join-Path $skills ('.stage.' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        New-Item -ItemType Directory -Path $stage | Out-Null

        # Finish a swap that an earlier run did not finish.
        $old = "$skill.old"
        if (Test-Path -LiteralPath $old) {
            if (Test-Path -LiteralPath $skill) { Remove-Item -LiteralPath $old -Recurse -Force }
            else { Move-Item -LiteralPath $old -Destination $skill }
        }

        # 2. fetch
        $new = Join-Path $stage 'second-brain'
        if ($env:BRAIN_KIT_SOURCE) {
            $src = Join-Path $env:BRAIN_KIT_SOURCE 'skills\second-brain'
            if (-not (Test-Path -LiteralPath (Join-Path $src 'SKILL.md'))) {
                throw "BRAIN_KIT_SOURCE=$($env:BRAIN_KIT_SOURCE) has no skills\second-brain\SKILL.md"
            }
            Copy-Item -LiteralPath $src -Destination $new -Recurse
        } else {
            $zip = Join-Path $stage 'src.zip'
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            if (-not $ref) { $ref = Get-LatestRelease $repo }
            try {
                Invoke-WebRequest -UseBasicParsing -Uri "https://codeload.github.com/$repo/zip/$ref" -OutFile $zip
            } catch { throw "could not download $repo@$ref. $($_.Exception.Message)" }
            $unz = Join-Path $stage 'src'
            try { Expand-Archive -LiteralPath $zip -DestinationPath $unz }
            catch { throw "the download of $repo@$ref is not a valid archive." }
            $top = @(Get-ChildItem -LiteralPath $unz -Directory)
            if ($top.Count -ne 1 -or -not (Test-Path -LiteralPath (Join-Path $top[0].FullName 'skills\second-brain\SKILL.md'))) {
                throw 'the download has no skills\second-brain\SKILL.md.'
            }
            Move-Item -LiteralPath (Join-Path $top[0].FullName 'skills\second-brain') -Destination $new
        }
        Get-ChildItem -LiteralPath $new -Recurse -Force -Directory -Filter '__pycache__' |
            Remove-Item -Recurse -Force
        $cliNew = Join-Path $new 'scripts\brain'
        $version = Invoke-Python $py @('-B', $cliNew, '--version')
        if ($LASTEXITCODE -ne 0 -or -not $version) { throw "the downloaded CLI does not run: $version" }
        $source = if ($env:BRAIN_KIT_SOURCE) { "local:$($env:BRAIN_KIT_SOURCE)" } else { "$repo@$ref" }
        $receipt = [ordered]@{
            version      = ($version -replace '^second-brain ', '')
            source       = $source
            method       = 'install.ps1'
            installed_at = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        $json = (($receipt | ConvertTo-Json) -replace "`r`n", "`n") + "`n"
        [IO.File]::WriteAllText((Join-Path $stage 'install.json'), $json, (New-Object Text.UTF8Encoding $false))

        # Swap. Each step is a rename; a crash between them is repaired by the next run.
        if (Test-Path -LiteralPath $skill) { Move-Item -LiteralPath $skill -Destination $old }
        Move-Item -LiteralPath $new -Destination $skill
        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Recurse -Force }
        Move-Item -LiteralPath (Join-Path $stage 'install.json') -Destination (Join-Path $data 'install.json') -Force
        Write-Output "installed: $skill"

        # 3. links
        Set-Link $skill (Join-Path $home_ '.claude\skills\second-brain')   # Claude Code
        Set-Link $skill (Join-Path $home_ '.agents\skills\second-brain')   # Codex, Cursor
        if (Test-Path -LiteralPath (Join-Path $home_ '.cursor') -PathType Container) {
            Set-Link $skill (Join-Path $home_ '.cursor\skills\second-brain')
        }
        if (Test-Path -LiteralPath (Join-Path $home_ '.kiro') -PathType Container) {
            Set-Link $skill (Join-Path $home_ '.kiro\skills\second-brain')
        }

        $cli = Join-Path $skill 'scripts\brain'
        $pyCmd = ($py -join ' ')
        Write-Output "python:    $pyCmd"
        Write-Output "cli:       $cli"
        Write-Output "version:   $version"
        Write-Output "source:    $source"
        Write-Output 'next:      ask the user for their work vault folder, personal vault folder and name, then run'
        Write-Output "           $pyCmd `"$cli`" init --work-vault <work-folder> --personal-vault <personal-folder> --owner `"<Full Name>`""
        Write-Output 'done.'
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
    }
}

# The tag of the latest GitHub release, read from where /releases/latest
# redirects (no API call, no rate limit). Never falls back to main: that would
# quietly install unreleased code.
function Get-LatestRelease($repo) {
    $loc = $null
    try {
        $req = [Net.HttpWebRequest]::Create("https://github.com/$repo/releases/latest")
        $req.Method = 'HEAD'
        $req.AllowAutoRedirect = $false
        $req.UserAgent = 'brain-kit-installer'
        try { $resp = $req.GetResponse() } catch [Net.WebException] { $resp = $_.Exception.Response }
        if ($resp) { $loc = $resp.Headers['Location']; $resp.Close() }
    } catch { $loc = $null }
    if ("$loc" -match '/releases/tag/([A-Za-z0-9._-]+)$') { return $Matches[1] }
    throw 'could not find the latest brain-kit release. Check your connection, or pick a version with $env:BRAIN_KIT_REF = ''<tag>''.'
}

# Returns the command (as an array) of the first Python 3.9+ that really runs.
# The Microsoft Store alias "python.exe" exists but only opens the Store, so a
# candidate counts only if it prints its version.
function Find-Python {
    foreach ($cand in @(@('py', '-3'), @('python3'), @('python'))) {
        if (-not (Get-Command $cand[0] -CommandType Application -ErrorAction SilentlyContinue)) { continue }
        $out = Invoke-Python $cand @('-c', 'import sys; print(1 if sys.version_info >= (3, 9) else 0)')
        if ($LASTEXITCODE -eq 0 -and "$out".Trim() -eq '1') { return , $cand }
    }
    return $null
}

function Invoke-Python($py, [string[]]$argv) {
    # In Windows PowerShell 5.1, stderr from a native program becomes an error
    # record, and 'Stop' would turn a harmless warning into a failure.
    $ErrorActionPreference = 'Continue'
    $exe = $py[0]
    $pre = @($py | Select-Object -Skip 1)
    try { $out = & $exe @pre @argv 2>&1 | Out-String } catch { $global:LASTEXITCODE = 1; return '' }
    return $out.Trim()
}

# The target of a junction or symlink, or $null for anything else.
function Get-LinkTarget($path) {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if (-not $item -or -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $null }
    $t = @($item.Target)[0]
    if ($t) { $t = $t -replace '^\\\\\?\\', '' -replace '^\\\?\?\\', '' }
    return $t
}

# A link target is brain-kit's if it is a brain-kit skill copy, wherever an
# earlier run put it.
function Test-Ours($target) {
    return [bool]($target -and ($target.TrimEnd('\') -match '\\brain-kit\\skills\\second-brain$'))
}

# Create or repoint a junction, but only in an empty slot or over our own link.
function Set-Link($target, $path) {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    $cur = Get-LinkTarget $path
    if ($item -and $cur -and $cur.TrimEnd('\') -eq $target.TrimEnd('\')) {
        Write-Output "linked:    $path"
        return
    }
    if ($item -and (Test-Ours $cur)) {
        # Directory.Delete on a junction removes the link only, never the target.
        [IO.Directory]::Delete($path, $false)
        New-Item -ItemType Junction -Path $path -Target $target | Out-Null
        Write-Output "linked:    $path (updated from $cur)"
        return
    }
    if ($item) {
        Write-Output "skipped:   $path (already exists and is not brain-kit's; left it alone)"
        return
    }
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
        New-Item -ItemType Junction -Path $path -Target $target | Out-Null
        Write-Output "linked:    $path"
    } catch {
        Write-Output "skipped:   $path (could not create it)"
    }
}

Install-BrainKit
