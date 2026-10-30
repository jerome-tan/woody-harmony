param(
  [Parameter(Mandatory = $true)][string]$ArchivePath,
  [Parameter(Mandatory = $true)][string]$UnpackedPath
)

$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path -LiteralPath $UnpackedPath).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("woody-zip-" + [Guid]::NewGuid().ToString('N'))
$appDirectory = Join-Path $testRoot 'Woody portable 中文'
$profileDirectory = Join-Path $testRoot 'profile'
$appProcess = $null

try {
  Expand-Archive -LiteralPath $ArchivePath -DestinationPath $appDirectory
  foreach ($required in @('Woody.exe', 'resources/app.asar', 'icudtl.dat', 'resources.pak', 'locales/en-US.pak')) {
    if (-not (Test-Path -LiteralPath (Join-Path $appDirectory $required) -PathType Leaf)) {
      throw "Missing portable runtime file: $required"
    }
  }

  # NSIS may add its elevation helper after the ZIP target has finished.
  # This installer-only helper is optional for the directory app.
  $expected = @{}
  foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -File -Recurse) {
    $relative = [IO.Path]::GetRelativePath($sourceRoot, $file.FullName).Replace('\', '/')
    if ($relative -ne 'resources/elevate.exe') {
      $expected[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
  }
  $checked = 0
  foreach ($file in Get-ChildItem -LiteralPath $appDirectory -File -Recurse) {
    $relative = [IO.Path]::GetRelativePath($appDirectory, $file.FullName).Replace('\', '/')
    if ($relative -eq 'resources/elevate.exe') { continue }
    if (-not $expected.ContainsKey($relative)) { throw "Unexpected ZIP entry: $relative" }
    if ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne $expected[$relative]) {
      throw "Portable file differs from packaged app: $relative"
    }
    $checked++
  }
  if ($checked -ne $expected.Count) { throw "ZIP contains $checked of $($expected.Count) runtime files" }
  Write-Host "Portable ZIP verified: $checked runtime files match SHA-256"

  New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
  $appProcess = Start-Process -FilePath (Join-Path $appDirectory 'Woody.exe') `
    -WorkingDirectory $appDirectory -ArgumentList "--user-data-dir=`"$profileDirectory`"" -PassThru
  $deadline = [DateTime]::UtcNow.AddSeconds(30)
  do {
    Start-Sleep -Milliseconds 200
    $appProcess.Refresh()
    if ($appProcess.HasExited) { throw "Portable app exited during startup: $($appProcess.ExitCode)" }
  } while ($appProcess.MainWindowHandle -eq 0 -and [DateTime]::UtcNow -lt $deadline)
  if ($appProcess.MainWindowHandle -eq 0) { throw 'Portable app did not open a window' }
  Start-Sleep -Seconds 2
  $appProcess.Refresh()
  if ($appProcess.HasExited -or $appProcess.MainWindowTitle -ne 'Woody') {
    throw 'Portable app did not keep its Woody window open'
  }
  Write-Host "Portable app launched from: $appDirectory"
  if (-not $appProcess.CloseMainWindow() -or -not $appProcess.WaitForExit(10000)) {
    throw 'Portable app did not close normally'
  }
  if ($appProcess.ExitCode -ne 0) { throw "Portable app exit code: $($appProcess.ExitCode)" }
  Write-Host 'Portable app opened and closed successfully'
} finally {
  if ($null -ne $appProcess -and -not $appProcess.HasExited) {
    Stop-Process -Id $appProcess.Id -Force
    $appProcess.WaitForExit(5000) | Out-Null
  }
  if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
