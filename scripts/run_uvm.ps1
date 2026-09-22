# =============================================================================
# run_uvm.ps1 -- compile + elaborate + run the UVM testbench in Vivado xsim
#
# Usage (from the repo root, in a PowerShell where Vivado's bin is on PATH):
#   .\scripts\run_uvm.ps1                       # smoke_test
#   .\scripts\run_uvm.ps1 -Test random_test     # constrained-random test
#   .\scripts\run_uvm.ps1 -Test random_test -Seed 7
#   .\scripts\run_uvm.ps1 -Gui                  # open waveform GUI
# =============================================================================
param(
  [string]$Test = "smoke_test",
  [int]$Seed = 1,
  [switch]$Gui
)
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $root "build\xsim"
New-Item -ItemType Directory -Force -Path $work | Out-Null
Push-Location $work

$src = @(
  "$root\rtl\axi2apb_bridge.sv",
  "$root\rtl\apb_slave_mem.sv",
  "$root\rtl\axi2apb_top.sv",
  "$root\sva\axi2apb_sva.sv",
  "$root\tb_uvm\axi_lite_if.sv",
  "$root\tb_uvm\axi2apb_pkg.sv",
  "$root\tb_uvm\tb_top.sv"
)

try {
  Write-Host "== xvlog: compiling ==" -ForegroundColor Cyan
  xvlog -sv -L uvm @src
  if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }

  Write-Host "== xelab: elaborating ==" -ForegroundColor Cyan
  xelab tb_top -L uvm -relax -timescale 1ns/1ps -debug typical -s tb_sim
  if ($LASTEXITCODE -ne 0) { throw "xelab failed" }

  $plusargs = @("-testplusarg", "UVM_TESTNAME=$Test",
                "-testplusarg", "UVM_VERBOSITY=UVM_LOW",
                "-sv_seed", "$Seed")

  if ($Gui) {
    Write-Host "== xsim GUI ==" -ForegroundColor Cyan
    xsim tb_sim -gui @plusargs
  } else {
    Write-Host "== xsim: running $Test (seed $Seed) ==" -ForegroundColor Cyan
    xsim tb_sim -R @plusargs -log "$work\$Test.log"
    Write-Host "Log saved to build\xsim\$Test.log"
  }
} finally {
  Pop-Location
}
