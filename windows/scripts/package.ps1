$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot)
try {
    $version=(Get-Content package.json | ConvertFrom-Json).version
    $output=Join-Path $PWD 'artifacts'
    $portable=Join-Path $output 'portable'
    New-Item -ItemType Directory -Force $portable | Out-Null
    Copy-Item src-tauri/target/release/Siftly.exe $portable
    Copy-Item README.md,THIRD_PARTY_NOTICES.md $portable
    Copy-Item licenses $portable -Recurse -Force
    Compress-Archive -Path "$portable/*" -DestinationPath "$output/Siftly-$version-Windows-x64-portable.zip" -Force
    # Include the complete build inputs so the statically linked LGPL RAW decoder can be rebuilt/relinked.
    $source=Join-Path $output 'source'
    New-Item -ItemType Directory -Force $source | Out-Null
    Copy-Item src,public,scripts,licenses,e2e $source -Recurse -Force
    New-Item -ItemType Directory -Force "$source/src-tauri" | Out-Null
    Copy-Item src-tauri/src,src-tauri/icons,src-tauri/capabilities "$source/src-tauri" -Recurse -Force
    Copy-Item src-tauri/*.toml,src-tauri/*.json,src-tauri/*.rs,src-tauri/Cargo.lock "$source/src-tauri" -Force
    Copy-Item *.json,*.ts,*.html,*.md $source -Force
    New-Item -ItemType Directory -Force "$source/.cargo" | Out-Null
    & cargo vendor --locked --manifest-path src-tauri/Cargo.toml "$source/vendor" | Set-Content -Encoding utf8NoBOM "$source/.cargo/config.toml"
    if ($LASTEXITCODE) { throw 'Unable to collect source dependencies' }
    @'
[source.crates-io]
replace-with = "vendored-sources"
[source.vendored-sources]
directory = "vendor"
'@ | Set-Content -Encoding utf8NoBOM "$source/.cargo/config.toml"
    Compress-Archive -Path "$source/*","$source/.cargo" -DestinationPath "$output/Siftly-$version-source.zip" -Force
    Get-ChildItem "$output/*.zip",'src-tauri/target/release/bundle/nsis/*-setup.exe','src-tauri/target/release/bundle/msi/*.msi' | ForEach-Object {
        $hash=(Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $($_.Name)"
    } | Set-Content -Encoding utf8NoBOM "$output/SHA256SUMS.txt"
} finally { Pop-Location }
