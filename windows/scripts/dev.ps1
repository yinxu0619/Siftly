param([ValidateSet('dev','test','build')][string]$Task='dev')
$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot)
try {
    foreach ($tool in @('node','npm','cargo')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Missing $tool. See windows/README.md for prerequisites." }
    }
    if (-not (Test-Path node_modules)) { & npm.cmd ci; if ($LASTEXITCODE) { throw 'npm ci failed' } }
    switch ($Task) {
        'dev' { & npm.cmd run tauri -- dev }
        'test' {
            & npm.cmd test; if ($LASTEXITCODE) { throw 'Frontend tests failed' }
            & npm.cmd run build; if ($LASTEXITCODE) { throw 'Frontend build failed' }
            & cargo test --manifest-path src-tauri/Cargo.toml --locked --lib
        }
        'build' { & npm.cmd run tauri -- build --bundles nsis,msi }
    }
    if ($LASTEXITCODE) { throw "$Task failed" }
} finally { Pop-Location }
