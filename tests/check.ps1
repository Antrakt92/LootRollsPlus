Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$addonRoot = Split-Path -Parent $PSScriptRoot
$luaFiles = Get-ChildItem -LiteralPath $addonRoot -Recurse -Filter '*.lua' -File
foreach ($file in $luaFiles) {
    & luac5.1 -p $file.FullName
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$tests = [ordered]@{
    test_history = Join-Path $addonRoot 'History.lua'
    test_gear = Join-Path $addonRoot 'Gear.lua'
    test_capture = $addonRoot
    test_inspect = $addonRoot
    test_roll_display = $addonRoot
    test_live_rolls = $addonRoot
    test_live_source = $addonRoot
    test_addon = $addonRoot
}
foreach ($test in $tests.GetEnumerator()) {
    & lua5.1 (Join-Path $PSScriptRoot "$($test.Key).lua") $test.Value
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
