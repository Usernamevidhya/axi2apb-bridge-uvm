# run_synth.ps1 -- run the Vivado synthesis/implementation flow in batch mode
# Usage (repo root):  .\scripts\run_synth.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  vivado -mode batch -source scripts/synth.tcl -log build/vivado.log -journal build/vivado.jou
} finally {
  Pop-Location
}
