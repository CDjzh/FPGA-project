param([Parameter(Mandatory=$true)][string]$TdExe)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
if (!(Test-Path -LiteralPath $TdExe)) { throw 'TD executable not found.' }
if (!(Test-Path -LiteralPath (Join-Path $taskRoot '.local_paths.json'))) { throw 'Run python tools/configure_project.py first.' }
foreach ($taskStage in @('synth','physical')) {
 $taskScript=Join-Path $taskRoot ('fpga/project/'+$taskStage+'.tcl')
 $taskLog=Join-Path $taskRoot ('build/'+$taskStage+'.log')
 & $TdExe ($taskScript -replace '\\','/') *> $taskLog
 $taskMarker=if ($taskStage -eq 'synth') {'TINGJIAN_SYNTHESIS_FINISHED'} else {'TINGJIAN_PHYSICAL_FINISHED'}
 if ($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $taskLog -Pattern $taskMarker -Quiet)) { throw ('Build failed: '+$taskLog) }
}
Write-Output 'Built fpga/project/Tingjian_Runs/phy_1/Tingjian.bit. Review timing and ROM initialization before download.'
