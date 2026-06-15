param(
  [string]$VersionType = "patch"
)

# Ensure gh is in PATH
$ghPaths = @(
  "C:\Program Files\GitHub CLI\gh.exe",
  "$env:LOCALAPPDATA\Programs\GitHub CLI\gh.exe",
  "$env:USERPROFILE\scoop\shims\gh.exe"
)
$ghExe = $ghPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ghExe) {
  $ghExe = Get-Command gh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}
if (-not $ghExe) { Write-Error "gh CLI not found. Install from https://cli.github.com/"; exit 1 }

$env:PATH = "$(Split-Path $ghExe -Parent);$env:PATH"

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
$apkName = "halalexpress-v$newVer.apk"

# Commit, tag, push
git add -A
git commit -m "release v$newVer"
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1) { Write-Error "Commit failed"; exit 1 }
git tag "v$newVer"
git push origin main --tags
if ($LASTEXITCODE -ne 0) { Write-Error "Push failed"; exit 1 }

# Create GitHub release
gh release create "v$newVer" `
  --title "HalalExpress v$newVer" `
  --notes "Release v$newVer" `
  "$($apkPath)#$apkName"

if ($?) { Write-Host "=== Release v$newVer created & APK uploaded! ===" }
