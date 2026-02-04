# Build Custom Drizzle Kit
# This script automates the build process for the custom drizzle-kit package

param(
    [switch]$SkipOrmBuild,
    [switch]$Clean
)

$ErrorActionPreference = "Continue"
$RootDir = $PSScriptRoot

function Write-Step {
    param([string]$Step, [string]$Message, [string]$Color = "Yellow")
    Write-Host "[$Step] $Message" -ForegroundColor $Color
}

function Write-Detail {
    param([string]$Message, [string]$Color = "Gray")
    Write-Host "  - $Message" -ForegroundColor $Color
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Custom Drizzle Kit Build Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Clean previous builds if requested
if ($Clean) {
    Write-Step "1/5" "Cleaning previous builds..."

    if (Test-Path "$RootDir\drizzle-orm\dist") {
        Remove-Item -Recurse -Force "$RootDir\drizzle-orm\dist"
        Write-Detail "Removed drizzle-orm/dist"
    }
    if (Test-Path "$RootDir\drizzle-orm\dist.new") {
        Remove-Item -Recurse -Force "$RootDir\drizzle-orm\dist.new"
        Write-Detail "Removed drizzle-orm/dist.new"
    }
    if (Test-Path "$RootDir\drizzle-orm\dist-dts") {
        Remove-Item -Recurse -Force "$RootDir\drizzle-orm\dist-dts"
        Write-Detail "Removed drizzle-orm/dist-dts"
    }
    if (Test-Path "$RootDir\drizzle-kit\dist") {
        Remove-Item -Recurse -Force "$RootDir\drizzle-kit\dist"
        Write-Detail "Removed drizzle-kit/dist"
    }
    Get-ChildItem "$RootDir\drizzle-kit\*.tgz" -ErrorAction SilentlyContinue | Remove-Item -Force
    Write-Detail "Removed previous tarballs"
    Write-Host ""
}

# Step 1: Build drizzle-orm
if (-not $SkipOrmBuild) {
    Write-Step "1/5" "Building drizzle-orm..."

    Push-Location "$RootDir\drizzle-orm"
    try {
        # Run prisma generate
        Write-Detail "Running prisma generate..."
        & pnpm run p 2>&1 | Out-Null

        # Run the build script
        Write-Detail "Running build script (this may take a while)..."
        & pnpm tsx scripts/build.ts 2>&1 | ForEach-Object {
            if ($_ -match "error|Error|ERROR") {
                Write-Host $_ -ForegroundColor Red
            }
        }

        if (-not (Test-Path "$RootDir\drizzle-orm\dist\index.js")) {
            Write-Host "ERROR: drizzle-orm build failed - dist/index.js not found" -ForegroundColor Red
            exit 1
        }
        Write-Detail "drizzle-orm built successfully" "Green"
    }
    finally {
        Pop-Location
    }
    Write-Host ""
} else {
    Write-Step "1/5" "Skipping drizzle-orm build (using existing)" "Gray"
    Write-Host ""
}

# Step 2: Build drizzle-kit
Write-Step "2/5" "Building drizzle-kit..."

Push-Location "$RootDir\drizzle-kit"
try {
    # Clean dist folder
    if (Test-Path "dist") {
        Remove-Item -Recurse -Force "dist"
    }

    # Run the build
    Write-Detail "Cleaning dist folder..."
    & node scripts/clean-dist.js 2>&1 | Out-Null

    Write-Detail "Running tsup builds (this may take a while)..."
    & pnpm tsx build.ts 2>&1 | ForEach-Object {
        $line = $_
        if ($line -match "Build success|Building entry") {
            # Show build progress
        }
        if ($line -match "error|Error|ERROR" -and $line -notmatch "warning") {
            Write-Host $line -ForegroundColor Red
        }
    }

    # Copy files
    Write-Detail "Copying package files..."
    & node scripts/copy-files.js 2>&1 | Out-Null

    if (-not (Test-Path "$RootDir\drizzle-kit\dist\bin.cjs")) {
        Write-Host "ERROR: drizzle-kit build failed - dist/bin.cjs not found" -ForegroundColor Red
        exit 1
    }
    Write-Detail "drizzle-kit built successfully" "Green"
}
finally {
    Pop-Location
}
Write-Host ""

# Step 3: Prepare dist/package.json for packaging
Write-Step "3/5" "Preparing package.json for distribution..."

$distPackageJsonPath = "$RootDir\drizzle-kit\dist\package.json"
$distPackageJson = Get-Content $distPackageJsonPath -Raw | ConvertFrom-Json

# Remove scripts and devDependencies
$distPackageJson.scripts = @{}
if ($distPackageJson.PSObject.Properties['devDependencies']) {
    $distPackageJson.PSObject.Properties.Remove('devDependencies')
}

# Write cleaned package.json
$distPackageJson | ConvertTo-Json -Depth 10 | Set-Content $distPackageJsonPath -Encoding UTF8
Write-Detail "Cleaned package.json" "Green"
Write-Host ""

# Step 4: Create tarball
Write-Step "4/5" "Creating package tarball..."

Push-Location "$RootDir\drizzle-kit\dist"
try {
    # Capture npm pack output, ignore stderr notices
    $packOutput = & npm pack --pack-destination .. 2>&1
    $tarballName = $packOutput | Where-Object { $_ -match "\.tgz$" } | Select-Object -First 1
    if (-not $tarballName) {
        $tarballName = $packOutput | Select-Object -First 1
    }
}
finally {
    Pop-Location
}

$tarball = Get-ChildItem "$RootDir\drizzle-kit\drizzle-kit-*.tgz" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($tarball) {
    Write-Detail "Created: $($tarball.Name)" "Green"
} else {
    Write-Host "ERROR: Failed to create tarball" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 5: Verify build
Write-Step "5/5" "Verifying build..."

$versionOutput = & node "$RootDir\drizzle-kit\dist\bin.cjs" --version 2>&1
$versionOutput | ForEach-Object { Write-Detail $_ "Green" }
Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Build Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Output files:" -ForegroundColor White
Write-Host "  Dist folder: " -NoNewline; Write-Host "drizzle-kit\dist\" -ForegroundColor Yellow
Write-Host "  Tarball:     " -NoNewline; Write-Host "drizzle-kit\$($tarball.Name)" -ForegroundColor Yellow
Write-Host ""
Write-Host "To install in another project:" -ForegroundColor White
Write-Host "  npm install $($tarball.FullName)" -ForegroundColor Cyan
Write-Host ""
