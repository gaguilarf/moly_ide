<#
.SYNOPSIS
  Publica una version nueva de Moly IDE en el endpoint de actualizaciones del Jetson.

.DESCRIPTION
  Compila el APK de release, escribe version.json y sube ambos por scp a
  /home/jetson/ragnar_orquestador_back/updates/, que el backend (Ragnar Group API)
  sirve publicamente en https://panel.ragnargroup.app/updates/. La app movil
  (UpdateCubit) consulta ese mismo dominio por defecto, asi que no hace falta
  tocar nada mas para que detecte la version nueva.

  Antes de correr esto: subir `version:` en pubspec.yaml (formato 1.0.0+N).

.PARAMETER ReleaseNotes
  Texto de notas de version que vera la app en el dialogo de actualizacion.
#>
param(
    [string]$ReleaseNotes = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host "Compilando APK de release..." -ForegroundColor Cyan
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw "flutter build apk fallo (exit $LASTEXITCODE)" }

$metadataPath = Join-Path $repoRoot "build\app\outputs\apk\release\output-metadata.json"
$metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json
$element = $metadata.elements[0]
$versionName = $element.versionName
$buildNumber = $element.versionCode

Write-Host "Version detectada: $versionName+$buildNumber" -ForegroundColor Cyan

$versionJson = [ordered]@{
    version       = "$versionName+$buildNumber"
    version_name  = $versionName
    build_number  = $buildNumber
    apk_url       = "https://panel.ragnargroup.app/updates/app-release.apk"
    release_notes = $ReleaseNotes
    updated_at    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

$apkDir = Join-Path $repoRoot "build\app\outputs\flutter-apk"
$versionJsonPath = Join-Path $apkDir "version.json"
$apkPath = Join-Path $apkDir "app-release.apk"

$versionJsonText = $versionJson | ConvertTo-Json
# Set-Content -Encoding utf8 escribe BOM en Windows PowerShell 5.1, y un BOM al
# inicio de version.json rompe el parseo JSON del lado del cliente. Se escribe
# a mano en UTF-8 sin BOM.
[System.IO.File]::WriteAllText($versionJsonPath, $versionJsonText, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Escrito $versionJsonPath" -ForegroundColor Cyan

Write-Host "Subiendo al Jetson por scp..." -ForegroundColor Cyan
& scp $apkPath jetson:/home/jetson/ragnar_orquestador_back/updates/app-release.apk
if ($LASTEXITCODE -ne 0) { throw "scp del APK fallo (exit $LASTEXITCODE)" }
& scp $versionJsonPath jetson:/home/jetson/ragnar_orquestador_back/updates/version.json
if ($LASTEXITCODE -ne 0) { throw "scp de version.json fallo (exit $LASTEXITCODE)" }

Write-Host "Verificando el endpoint publico..." -ForegroundColor Cyan
$check = Invoke-RestMethod -Uri "https://panel.ragnargroup.app/updates/version.json"
if ($check.version -ne "$versionName+$buildNumber") {
    throw "El servidor responde version '$($check.version)', se esperaba '$versionName+$buildNumber'"
}

Write-Host "Publicado: v$versionName+$buildNumber en https://panel.ragnargroup.app/updates/" -ForegroundColor Green
