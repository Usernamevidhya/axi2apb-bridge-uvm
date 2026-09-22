// =============================================================================
// tb_top.sv -- UVM testbench top: clock, reset, interface, DUT, run_test()
// =============================================================================
`timescale 1ns/1ps

module tb_top;
  import uvm_pkg::*;
  import axi2apb_pkg::*;
  `include "uvm_macros.svh"

  logic aclk = 0;
  logic aresetn;

  always #5 aclk = ~aclk;                 // 100 MHz

  initial begin
    aresetn = 0;
    repeat (5) @(posedge aclk);
    aresetn = 1;
  end

  axi_lite_if vif (.aclk(aclk), .aresetn(aresetn));

  axi2apb_top dut (
    .aclk      (aclk),          .aresetn   (aresetn),     .wait_cfg  (vif.wait_cfg),
    .s_awaddr  (vif.awaddr),    .s_awprot  (vif.awprot),
    .s_awvalid (vif.awvalid),   .s_awready (vif.awready),
    .s_wdata   (vif.wdata),     .s_wstrb   (vif.wstrb),
    .s_wvalid  (vif.wvalid),    .s_wready  (vif.wready),
    .s_bresp   (vif.bresp),     .s_bvalid  (vif.bvalid),  .s_bready  (vif.bready),
    .s_araddr  (vif.araddr),    .s_arprot  (vif.arprot),
    .s_arvalid (vif.arvalid),   .s_arready (vif.arready),
    .s_rdata   (vif.rdata),     .s_rresp   (vif.rresp),
    .s_rvalid  (vif.rvalid),    .s_rready  (vif.rready)
  );

  // Attach the SVA protocol checker to the DUT without touching the RTL
  bind axi2apb_top axi2apb_sva u_sva (
    .aclk      (aclk),      .aresetn   (aresetn),
    .s_awaddr  (s_awaddr),  .s_awvalid (s_awvalid), .s_awready (s_awready),
    .s_wdata   (s_wdata),   .s_wstrb   (s_wstrb),   .s_wvalid  (s_wvalid),  .s_wready (s_wready),
    .s_bresp   (s_bresp),   .s_bvalid  (s_bvalid),  .s_bready  (s_bready),
    .s_araddr  (s_araddr),  .s_arvalid (s_arvalid), .s_arready (s_arready),
    .s_rdata   (s_rdata),   .s_rresp   (s_rresp),   .s_rvalid  (s_rvalid),  .s_rready (s_rready),
    .paddr     (paddr),     .psel      (psel),      .penable   (penable),
    .pwrite    (pwrite),    .pwdata    (pwdata),    .pstrb     (pstrb),
    .pready    (pready),    .pslverr   (pslverr)
  );

  initial begin
    uvm_config_db#(virtual axi_lite_if)::set(null, "*", "vif", vif);
    run_test();        // test chosen with +UVM_TESTNAME=smoke_test / random_test
  end

endmodule
