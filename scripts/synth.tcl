# =============================================================================
# synth.tcl -- Vivado batch flow: synth -> place -> route -> reports
# Target: Zynq-7000 XC7Z007S (Real Digital Blackboard), out-of-context mode,
# so no pin assignments are needed.
#
# In the Vivado Tcl Console (no project open):
#     source <path-to>/axi2apb-bridge-uvm/scripts/synth.tcl
# or in batch mode:
#     vivado -mode batch -source scripts/synth.tcl
# =============================================================================
set root    [file normalize [file join [file dirname [info script]] ..]]
set part    xc7z007sclg400-1
set top     axi2apb_top
set outdir  [file join $root build vivado]
file mkdir $outdir

catch { close_project }
read_verilog -sv [glob [file join $root rtl *.sv]]
read_xdc [file join $root constraints axi2apb_ooc.xdc]

synth_design -top $top -part $part -mode out_of_context
write_checkpoint -force $outdir/post_synth.dcp
report_utilization    -file $outdir/utilization_synth.rpt

opt_design
place_design
route_design
write_checkpoint -force $outdir/post_route.dcp

report_utilization     -file $outdir/utilization_route.rpt
report_timing_summary  -file $outdir/timing_summary.rpt
report_timing -max_paths 5 -file $outdir/critical_paths.rpt

puts "=============================================================="
puts " Done. Reports are in $outdir"
puts "   utilization_route.rpt : LUTs / FFs / LUTRAM used"
puts "   timing_summary.rpt    : WNS (positive = timing met)"
puts "=============================================================="
