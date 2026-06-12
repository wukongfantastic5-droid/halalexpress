param(
  [string]$VersionType = "patch"
)

$path = "pubspec.yaml"
$content = Get-Content $path -Raw
$match = [regex]::Match($content, "version: (\d+)\.(\d+)\.(\d+)\+(\d+)")
if (-not $match) { Write-Error "Can't parse version in pubspec.yaml"; exit 1 }

$major = [int]$match.Groups[1].Value
$minor = [int]$match.Groups[2].Value
$patch = [int]$match.Groups[3].Value
$build = [int]$match.Groups[4].Value + 1

switch ($VersionType) {
  "major" { $major++; $minor = 0; $patch = 0 }
  "minor" { $minor++; $patch = 0 }
  "patch" { $patch++ }
  default { $patch++ }
}

$newVer = "$major.$minor.$patch"
$newFull = "$newVer+$build"
$content = $content -replace "version: .+", "version: $newFull"
$content | Set-Content $path
Write-Host "=== Bumped to $newFull ==="

flutter build apk --release
if (-not $?) { Write-Error "Build failed"; exit 1 }

$apkPath = "build\app\outputs\flutter-apk\app-release.apk"
$apkName = "bunnyfresh-v$newVer.apk"

gh release create "v$newVer" `
  --title "BunnyFresh v$newVer" `
  --notes "Release v$newVer" `
  "$apkPath#$apkName"

if ($?) { Write-Host "=== Release v$newVer created & APK uploaded! ===" }
