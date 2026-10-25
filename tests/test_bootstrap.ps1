$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
$bootstrap = Join-Path $sourceRoot 'deploy-kit\bootstrap.ps1'
$content = Get-Content -LiteralPath $bootstrap -Raw -Encoding UTF8
$marker = '$venv = Join-Path'
$index = $content.IndexOf($marker)
if ($index -lt 0) { throw 'Bootstrap routing boundary not found.' }
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('dafeiyu-bootstrap-test-' + [Guid]::NewGuid().ToString('N'))
$fixture = Join-Path $tempRoot 'source'
$kit = Join-Path $fixture 'deploy-kit'
New-Item -ItemType Directory -Force -Path $kit, (Join-Path $fixture 'plugin'), (Join-Path $fixture 'persona'), (Join-Path $fixture 'tests') | Out-Null
$probe = Join-Path $kit 'routing.ps1'
$probeText = $content.Substring(0,$index) + "`nWrite-Output `$Src`n"
[IO.File]::WriteAllText($probe,$probeText,[Text.UTF8Encoding]::new($true))
$global:dafeiyuBootstrapTestCalls = @()
function git {
    $global:dafeiyuBootstrapTestCalls += ,@($args)
    if ($args[0] -eq 'clone') {
        $dest = [string]$args[-1]
        New-Item -ItemType Directory -Force -Path (Join-Path $dest '.git'), (Join-Path $dest 'plugin'), (Join-Path $dest 'persona'), (Join-Path $dest 'tests') | Out-Null
    }
    $global:LASTEXITCODE = 0
}
$inPlace = & $probe
if ([string]$inPlace -ne $fixture) { throw 'In-place routing failed.' }
$target = Join-Path $tempRoot 'target with spaces'
$cloned = & $probe -Target $target -Upstream 'https://example.invalid/test.git'
if ([string]$cloned -ne $target -or $global:dafeiyuBootstrapTestCalls[-1][0] -ne 'clone') { throw 'Explicit Target did not clone.' }
$updated = & $probe -Target $target
if ([string]$updated -ne $target -or $global:dafeiyuBootstrapTestCalls[-1][0] -ne '-C') { throw 'Existing Target did not update.' }
. $probe | Out-Null
$caught = $false
try { Invoke-Checked 'powershell.exe' @('-NoProfile','-Command','exit 7') } catch { $caught = $_.Exception.Message -like '*exit code 7*' }
if (-not $caught) { throw 'Nonzero native exit code was not rejected.' }
Write-Output 'PASS: in-place routing; explicit Target; existing Target; native failures stop execution.'
$global:LASTEXITCODE = 0

