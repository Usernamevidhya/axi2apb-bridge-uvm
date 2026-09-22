// =============================================================================
// axi_lite_if.sv -- the "virtual interface" the UVM classes use to reach pins.
//
// Clocking blocks remove race conditions between testbench and DUT:
//   input  #1step : sample the value just BEFORE the clock edge
//   output #1     : drive 1 time unit AFTER the clock edge
// =============================================================================
interface axi_lite_if (input logic aclk, input logic aresetn);

  logic [31:0] awaddr;  logic [2:0] awprot;  logic awvalid;  logic awready;
  logic [31:0] wdata;   logic [3:0] wstrb;   logic wvalid;   logic wready;
  logic [1:0]  bresp;   logic bvalid;        logic bready;
  logic [31:0] araddr;  logic [2:0] arprot;  logic arvalid;  logic arready;
  logic [31:0] rdata;   logic [1:0] rresp;   logic rvalid;   logic rready;
  logic [3:0]  wait_cfg;   // testbench knob: APB slave wait states

  // Used by the driver (acts as AXI master)
  clocking drv_cb @(posedge aclk);
    default input #1step output #1;
    output awaddr, awprot, awvalid, wdata, wstrb, wvalid, bready,
           araddr, arprot, arvalid, rready, wait_cfg;
    input  awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid;
  endclocking

  // Used by the monitor (only watches)
  clocking mon_cb @(posedge aclk);
    default input #1step;
    input awaddr, awprot, awvalid, awready, wdata, wstrb, wvalid, wready,
          bresp, bvalid, bready, araddr, arprot, arvalid, arready,
          rdata, rresp, rvalid, rready, wait_cfg;
  endclocking

endinterface
