# Build Script for Njk Streaming APK
# Auto-cleans build folder and outputs to workspace

param(
    [string]$BuildType = "nonRoot_gameDebug",
    [switch]$Clean = $true
)

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Njk Streaming APK Builder" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# Configuration
$WorkspaceRoot = $PSScriptRoot
$OutputDir = Join-Path $WorkspaceRoot "output"
$AppBuildDir = if ($env:ARTEMIS_APP_BUILD_DIR) {
    $env:ARTEMIS_APP_BUILD_DIR
} else {
    Join-Path $env:TEMP "artemis-moonlight-build\app"
}

# Setup Java environment
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17.0.17.10-hotspot"
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

# Step 1: Kill any running Java processes
Write-Host "[1/5] Stopping Java processes..." -ForegroundColor Yellow
Get-Process -Name java -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# Step 2: Clean build directory if requested
# Uses cmd rd instead of Remove-Item to handle Windows long path (>260 chars) issues
if ($Clean) {
    Write-Host "[2/5] Cleaning build directory..." -ForegroundColor Yellow
    if (Test-Path $AppBuildDir) {
        cmd /c "rd /s /q `"$AppBuildDir`"" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  WARNING: Could not fully clean build directory (exit $LASTEXITCODE)" -ForegroundColor DarkYellow
        }
        Start-Sleep -Seconds 1
    }
} else {
    Write-Host "[2/5] Skipping clean (use -Clean to enable)..." -ForegroundColor Yellow
}

# Step 3: Create output directory
Write-Host "[3/5] Creating output directory..." -ForegroundColor Yellow
if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory | Out-Null
}

# Step 4: Build APK
Write-Host "[4/5] Building APK..." -ForegroundColor Yellow
Write-Host ""

Push-Location $WorkspaceRoot
# No need to run Gradle clean task - build dir was already deleted above
& .\gradlew.bat "app:assemble$BuildType" --no-daemon

$BuildSuccess = $LASTEXITCODE -eq 0
Pop-Location

if (-not $BuildSuccess) {
    Write-Host ""
    Write-Host "❌ Build FAILED!" -ForegroundColor Red
    exit 1
}

# Step 5: Copy APK to output
Write-Host ""
Write-Host "[5/5] Copying APK to output..." -ForegroundColor Yellow

# Determine APK path based on build type
$ApkPath = Join-Path $AppBuildDir "outputs\apk"
$ApkFile = Get-ChildItem -Path $ApkPath -Recurse -Filter "*.apk" | Where-Object { $_.Name -notlike "*unaligned*" } | Select-Object -First 1

if ($ApkFile) {
    # Get version from build.gradle
    $BuildGradle = Get-Content (Join-Path $WorkspaceRoot "app\build.gradle")
    $VersionName = ($BuildGradle | Select-String 'versionName "(.*)"').Matches.Groups[1].Value
    $VersionCode = ($BuildGradle | Select-String 'versionCode = (\d+)').Matches.Groups[1].Value
    
    $OutputFileName = "NjkStreaming-v$VersionName-build$VersionCode.apk"
    $OutputPath = Join-Path $OutputDir $OutputFileName
    
    Copy-Item -Path $ApkFile.FullName -Destination $OutputPath -Force
    
    $SizeMB = [math]::Round($ApkFile.Length / 1MB, 2)
    
    Write-Host ""
    Write-Host "==================================" -ForegroundColor Green
    Write-Host "✅ BUILD SUCCESS!" -ForegroundColor Green
    Write-Host "==================================" -ForegroundColor Green
    Write-Host "Version: $VersionName (build $VersionCode)" -ForegroundColor Cyan
    Write-Host "Size: $SizeMB MB" -ForegroundColor Cyan
    Write-Host "Output: $OutputPath" -ForegroundColor Cyan
    Write-Host ""
    
    # Open output folder
    explorer $OutputDir
} else {
    Write-Host ""
    Write-Host "❌ APK file not found!" -ForegroundColor Red
    exit 1
}
