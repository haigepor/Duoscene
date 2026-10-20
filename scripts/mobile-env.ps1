param(
    [string]$FlutterSdk = 'D:\fluttersdk\versions\3.47.6',
    [string]$AndroidSdk = 'D:\Android\Sdk',
    [string]$Jdk = 'D:\tools\jdk-21.0.12.1+1'
)

$ErrorActionPreference = 'Stop'
foreach ($requiredPath in @("$FlutterSdk\bin\flutter.bat", "$AndroidSdk\platform-tools\adb.exe", "$Jdk\bin\java.exe")) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Development tool missing: $requiredPath"
    }
}

# Dot-source this script to use the project's bundled Dart and JDK in this terminal.
$env:FLUTTER_BIN = Join-Path $FlutterSdk 'bin\flutter.bat'
$env:JAVA_HOME = $Jdk
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:Path = "$FlutterSdk\bin;$AndroidSdk\platform-tools;$AndroidSdk\cmdline-tools\19.0\bin;$Jdk\bin;" + $env:Path
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
