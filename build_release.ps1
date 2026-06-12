$pubspec = "pubspec.yaml"
$content = Get-Content $pubspec -Raw

$match = [regex]::Match($content, 'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)')
if ($match.Success) {
    $major = $match.Groups[1].Value
    $minor = $match.Groups[2].Value
    $patch = [int]$match.Groups[3].Value + 1
    $build = $match.Groups[4].Value
    $newVersion = "version: $major.$minor.$patch+$build"
    $oldVersion = $match.Groups[0].Value
    $content = $content -replace [regex]::Escape($oldVersion), $newVersion
    Set-Content $pubspec -Value $content -NoNewline
    Write-Host "Version bumped: $oldVersion -> $newVersion"
} else {
    Write-Host "Could not parse version from pubspec.yaml"
    exit 1
}

Write-Host "Building APK..."
flutter build apk --release
