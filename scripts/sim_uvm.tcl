# =============================================================================
# sim_uvm.tcl -- run the UVM testbench using ONLY Vivado (no extra installs)
#
# In the Vivado Tcl Console:
#     cd <path-to>/axi2apb-bridge-uvm          (use forward slashes /)
#     source scripts/sim_uvm.tcl                -> runs smoke_test
#
#     set test random_test ; source scripts/sim_uvm.tcl
#     set test random_test ; set seed 42 ; source scripts/sim_uvm.tcl
# =============================================================================
if {![info exists test]} { set test smoke_test }
if {![info exists seed]} { set seed 1 }

set root [file normalize [file join [file dirname [info script]] ..]]
set proj [file join $root build sim_proj]

# Close any project that is already open, then make a fresh simulation project
catch { close_sim -force }
catch { close_project }
create_project -force axi2apb_sim $proj -part xc7z007sclg400-1

# Order matters for SystemVerilog: RTL, checker, interface, package, top
set files [list \
  $root/rtl/axi2apb_bridge.sv \
  $root/rtl/apb_slave_mem.sv  \
  $root/rtl/axi2apb_top.sv    \
  $root/sva/axi2apb_sva.sv    \
  $root/tb_uvm/axi_lite_if.sv \
  $root/tb_uvm/axi2apb_pkg.sv \
  $root/tb_uvm/tb_top.sv ]
add_files -fileset sim_1 -norecurse $files
set_property file_type SystemVerilog [get_files $files]
set_property top     tb_top         [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# Tell xsim to use its built-in UVM library, and pass the test name
set sim [get_filesets sim_1]
set_property -name xsim.elaborate.xelab.more_options -value {-L uvm} -objects $sim
set_property -name xsim.elaborate.xelab.more_options -value {-L uvm -relax} -objects $sim
set_property -name xsim.simulate.xsim.more_options  \
  -value "-testplusarg UVM_TESTNAME=$test -testplusarg UVM_VERBOSITY=UVM_LOW -sv_seed $seed" \
  -objects $sim
set_property -name xsim.simulate.log_all_signals -value true -objects $sim

puts "=== Running $test (seed $seed) ==="
launch_simulation
catch { add_wave /tb_top/dut }
run all

puts "=============================================================="
puts " Look above for:  'Scoreboard: N passed, 0 failed'"
puts "                  'Functional coverage = X%'"
puts "                  'UVM_ERROR :    0'"
puts "=============================================================="
