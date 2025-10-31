# Post-build processing for Flutter web to enable proper cache busting
# Based on: https://lukasnevosad.medium.com/our-flutter-web-strategy-for-deferred-loading-instant-updates-happy-users-45ed90a7727c

$ErrorActionPreference = "Stop"

# Configuration
$BUILD_FOLDER = "build/web"
$DIST_FOLDER = "dist"

# Check if build folder exists
if (-not (Test-Path $BUILD_FOLDER)) {
    Write-Host "Error: Build folder '$BUILD_FOLDER' not found. Run 'flutter build web' first." -ForegroundColor Red
    exit 1
}

# Check if version.json exists
if (-not (Test-Path "$BUILD_FOLDER/version.json")) {
    Write-Host "Error: version.json not found in '$BUILD_FOLDER'. Make sure Flutter build completed successfully." -ForegroundColor Red
    exit 1
}

Write-Host "Starting post-build processing for Flutter web..." -ForegroundColor Green

# Extract version and build_number from version.json
$versionJson = Get-Content "$BUILD_FOLDER/version.json" -Raw | ConvertFrom-Json
$VERSION_BASE = $versionJson.version
$BUILD_NUMBER = $versionJson.build_number

if (-not $VERSION_BASE) {
    Write-Host "Error: Could not extract version from version.json" -ForegroundColor Red
    exit 1
}

if (-not $BUILD_NUMBER) {
    Write-Host "Error: Could not extract build_number from version.json" -ForegroundColor Red
    exit 1
}

# Combine into full version string (e.g., "1.0.0+123")
$VERSION = "${VERSION_BASE}+${BUILD_NUMBER}"

Write-Host "Detected version: $VERSION" -ForegroundColor Cyan

# Clean and create distribution directory
if (Test-Path $DIST_FOLDER) {
    Remove-Item $DIST_FOLDER -Recurse -Force
}
New-Item -ItemType Directory -Path $DIST_FOLDER -Force | Out-Null

# Move entire build output to versioned subdirectory
Write-Host "Moving build output to versioned directory: $DIST_FOLDER/$VERSION/" -ForegroundColor Yellow
Move-Item $BUILD_FOLDER "$DIST_FOLDER/$VERSION"

# Copy version.json to root (so it can be checked for updates)
Write-Host "Copying version.json to root..." -ForegroundColor Yellow
Copy-Item "$DIST_FOLDER/$VERSION/version.json" "$DIST_FOLDER/version.json"

# Move index.html to root
Write-Host "Moving index.html to root..." -ForegroundColor Yellow
Move-Item "$DIST_FOLDER/$VERSION/index.html" "$DIST_FOLDER/index.html"

# Modify <base href> in index.html to point to versioned directory
Write-Host "Updating <base href> to point to /$VERSION/..." -ForegroundColor Yellow

$indexContent = Get-Content "$DIST_FOLDER/index.html" -Raw
$indexContent = $indexContent -replace '<base href="/"', "<base href=""/$VERSION/"""
Set-Content "$DIST_FOLDER/index.html" -Value $indexContent

Write-Host "`nPost-build processing complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Distribution structure:"
Write-Host "  $DIST_FOLDER/"
Write-Host "    |-- index.html         (with base href pointing to /$VERSION/)"
Write-Host "    |-- version.json       (for update checks)"
Write-Host "    +-- $VERSION/"
Write-Host "        |-- flutter.js"
Write-Host "        |-- flutter_bootstrap.js"
Write-Host "        |-- main.dart.js"
Write-Host "        |-- *.part.js      (deferred chunks)"
Write-Host "        +-- assets/"
Write-Host ""
Write-Host "Deploy the contents of '$DIST_FOLDER/' to your hosting provider." -ForegroundColor Cyan
