# 大肥鱼部署引导：就地安装，或使用 -Target 克隆到指定目录。
[CmdletBinding()]
param(
    [string]$Target = "",
    [string]$Upstream = "https://github.com/whyever77/dafeiyu-astrbot.git"
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
function Say([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    $global:LASTEXITCODE = 0
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

# 明确的 -Target 优先；不指定时使用脚本所在仓库。
if ([string]::IsNullOrWhiteSpace($Target)) {
    $Src = $Root
    if (-not ((Test-Path -LiteralPath (Join-Path $Src 'plugin')) -and (Test-Path -LiteralPath (Join-Path $Src 'persona')))) {
        throw 'Current directory is not a project checkout; specify -Target.'
    }
    Say "就地引导: $Src"
} else {
    $Target = [IO.Path]::GetFullPath($Target)
    if (Test-Path -LiteralPath (Join-Path $Target '.git')) {
        Say "更新已有仓库: $Target"
        Invoke-Checked 'git' @('-C', $Target, 'pull', '--ff-only')
    } else {
        Say "克隆仓库: $Target"
        Invoke-Checked 'git' @('clone', '--depth', '1', $Upstream, $Target)
    }
    $Src = (Resolve-Path -LiteralPath $Target).Path
}
$Src = [IO.Path]::GetFullPath($Src)
foreach ($entry in @('plugin','persona','tests')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Src $entry))) { throw "Missing project directory: $entry" }
}

$venv = Join-Path $Src '.venv'
$py = Join-Path $venv 'Scripts\python.exe'
if (-not (Test-Path -LiteralPath $py)) { $py = Join-Path $venv 'bin\python' }
if (-not (Test-Path -LiteralPath $py)) {
    Say '创建虚拟环境'
    Invoke-Checked 'python' @('-m', 'venv', $venv)
    $py = Join-Path $venv 'Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $py)) { $py = Join-Path $venv 'bin\python' }
}
if (-not (Test-Path -LiteralPath $py)) { throw 'Virtual environment Python was not created.' }
Invoke-Checked $py @('-c', 'import sys; raise SystemExit(0 if sys.version_info >= (3,10) else 1)')

$requirements = Join-Path $PSScriptRoot 'requirements-plugin.txt'
$global:LASTEXITCODE = 0
& $py -m pip --version *> $null
$pipAvailable = $LASTEXITCODE -eq 0
Say '安装插件依赖'
if ($pipAvailable) {
    Invoke-Checked $py @('-m', 'pip', 'install', '-q', '--upgrade', 'pip')
    Invoke-Checked $py @('-m', 'pip', 'install', '-q', '-r', $requirements)
} elseif (Get-Command uv -ErrorAction SilentlyContinue) {
    Invoke-Checked 'uv' @('pip', 'install', '--python', $py, '-q', '-r', $requirements)
} else {
    Invoke-Checked $py @('-m', 'ensurepip', '--upgrade')
    Invoke-Checked $py @('-m', 'pip', 'install', '-q', '-r', $requirements)
}

$payload = [IO.Path]::GetFullPath((Join-Path $Src 'payload'))
# 只允许清理明确位于此仓库下的 payload，不跟随重解析目录。
if ([IO.Path]::GetDirectoryName($payload) -ne $Src.TrimEnd('\','/')) { throw 'Unsafe payload target.' }
if (Test-Path -LiteralPath $payload) {
    $item = Get-Item -LiteralPath $payload -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Payload cannot be a link.' }
    $links = @(Get-ChildItem -LiteralPath $payload -Recurse -Force | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
    if ($links.Count -gt 0) { throw 'Payload contains links; clean it manually.' }
    Remove-Item -LiteralPath $payload -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $payload 'plugins'), (Join-Path $payload 'persona') | Out-Null
Copy-Item (Join-Path $Src 'plugin\*') (Join-Path $payload 'plugins') -Recurse -Force
Copy-Item (Join-Path $Src 'persona\*.md') (Join-Path $payload 'persona') -Force
Say "已组装: $payload"

Say '运行离线测试'
Push-Location -LiteralPath $Src
try {
    Invoke-Checked $py @('tests/test_face_rules.py')
    Invoke-Checked $py @('tests/test_schedule_awareness.py')
} finally { Pop-Location }
Say '运行前置检查'
Invoke-Checked $py @((Join-Path $PSScriptRoot 'preflight.py'))
Say '部署辅助检查完成；尚需配置 AstrBot、NapCat、提供商与人格。详见 QUICKSTART.md。'
