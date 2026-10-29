param(
    [string]$FlutterSdk = $env:FLUTTER_ROOT,
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$Jdk = $env:JAVA_HOME
)

$ErrorActionPreference = 'Stop'
if (-not $PSScriptRoot) {
    $PSScriptRoot = Join-Path (Get-Location).Path 'scripts'
}
if (-not $FlutterSdk) {
    $flutterCommand = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if ($flutterCommand) { $FlutterSdk = Split-Path (Split-Path $flutterCommand.Source -Parent) -Parent }
}
if (-not $AndroidSdk) { $AndroidSdk = $env:ANDROID_SDK_ROOT }
if (-not $Jdk) {
    $javaCommand = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($javaCommand) { $Jdk = Split-Path (Split-Path $javaCommand.Source -Parent) -Parent }
}
if (-not $FlutterSdk -or -not $AndroidSdk -or -not $Jdk) {
    throw 'Set FLUTTER_ROOT, ANDROID_HOME and JAVA_HOME, or pass -FlutterSdk, -AndroidSdk and -Jdk.'
}
foreach ($requiredPath in @("$FlutterSdk\bin\flutter.bat", "$AndroidSdk\platform-tools\adb.exe", "$Jdk\bin\java.exe")) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Development tool missing: $requiredPath"
    }
}

# Dot-source this script to use the project's bundled Dart and JDK in this terminal.
$env:FLUTTER_BIN = Join-Path $FlutterSdk 'bin\flutter.bat'
$env:FLUTTER_ROOT = $FlutterSdk
$env:JAVA_HOME = $Jdk
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:Path = "$FlutterSdk\bin;$AndroidSdk\platform-tools;$Jdk\bin;" + $env:Path
$sdkManager = Join-Path $AndroidSdk 'cmdline-tools\latest\bin\sdkmanager.bat'
if (-not (Test-Path -LiteralPath $sdkManager)) {
    $sdkManager = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'cmdline-tools') -Filter sdkmanager.bat -Recurse -File |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if ($sdkManager) { $env:Path = (Split-Path $sdkManager -Parent) + ';' + $env:Path }
# native_toolchain_c 0.19.5 在中文 Windows 下使用系统代码页解码 vswhere 的 UTF-8 JSON。
# 项目内包装器仅转义 JSON Unicode；不替换系统安装器，也不改变查找到的 VS 实例。
$playerTools = Join-Path (Split-Path $PSScriptRoot -Parent) '.local\windows-tools'
$vswhereShim = Join-Path $playerTools 'vswhere.exe'
$vswhereSource = Join-Path $PSScriptRoot 'windows\vswhere-shim.cs'
if (Test-Path -LiteralPath $vswhereSource) {
    if (-not (Test-Path -LiteralPath $vswhereShim) -or (Get-Item -LiteralPath $vswhereSource).LastWriteTimeUtc -gt (Get-Item -LiteralPath $vswhereShim).LastWriteTimeUtc) {
        New-Item -ItemType Directory -Path $playerTools -Force | Out-Null
        $shimCompiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
        if (-not (Test-Path -LiteralPath $shimCompiler)) { throw 'C# compiler missing for the local vswhere UTF-8 adapter.' }
        & $shimCompiler /nologo /target:exe "/out:$vswhereShim" $vswhereSource
        if ($LASTEXITCODE -ne 0) { throw 'Unable to build local vswhere UTF-8 adapter.' }
    }
}
if (Test-Path -LiteralPath $vswhereShim) { $env:Path = "$playerTools;" + $env:Path }
Write-Output 'Duoscene Flutter/Android environment loaded for this terminal.'
