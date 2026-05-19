Set-StrictMode -Version Latest

function New-TestDirectory {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    [void](New-Item -ItemType Directory -Path $path -Force)
    $path
}
