// =============================================================================
// axi2apb_top.sv -- bridge + APB memory slave. This is the DUT for both the
// UVM and the cocotb testbenches, and the top for Vivado synthesis.
// =============================================================================
module axi2apb_top #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32
)(
  input  logic                 aclk,
  input  logic                 aresetn,
  input  logic [3:0]           wait_cfg,

  input  logic [ADDR_W-1:0]    s_awaddr,
  input  logic [2:0]           s_awprot,
  input  logic                 s_awvalid,
  output logic                 s_awready,
  input  logic [DATA_W-1:0]    s_wdata,
  input  logic [DATA_W/8-1:0]  s_wstrb,
  input  logic                 s_wvalid,
  output logic                 s_wready,
  output logic [1:0]           s_bresp,
  output logic                 s_bvalid,
  input  logic                 s_bready,
  input  logic [ADDR_W-1:0]    s_araddr,
  input  logic [2:0]           s_arprot,
  input  logic                 s_arvalid,
  output logic                 s_arready,
  output logic [DATA_W-1:0]    s_rdata,
  output logic [1:0]           s_rresp,
  output logic                 s_rvalid,
  input  logic                 s_rready
);

  logic [ADDR_W-1:0]   paddr;
  logic [2:0]          pprot;
  logic                psel, penable, pwrite, pready, pslverr;
  logic [DATA_W-1:0]   pwdata, prdata;
  logic [DATA_W/8-1:0] pstrb;

  axi2apb_bridge #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_bridge (
    .aclk      (aclk),      .aresetn   (aresetn),
    .s_awaddr  (s_awaddr),  .s_awprot  (s_awprot),  .s_awvalid (s_awvalid), .s_awready (s_awready),
    .s_wdata   (s_wdata),   .s_wstrb   (s_wstrb),   .s_wvalid  (s_wvalid),  .s_wready  (s_wready),
    .s_bresp   (s_bresp),   .s_bvalid  (s_bvalid),  .s_bready  (s_bready),
    .s_araddr  (s_araddr),  .s_arprot  (s_arprot),  .s_arvalid (s_arvalid), .s_arready (s_arready),
    .s_rdata   (s_rdata),   .s_rresp   (s_rresp),   .s_rvalid  (s_rvalid),  .s_rready  (s_rready),
    .m_paddr   (paddr),     .m_pprot   (pprot),     .m_psel    (psel),      .m_penable (penable),
    .m_pwrite  (pwrite),    .m_pwdata  (pwdata),    .m_pstrb   (pstrb),
    .m_prdata  (prdata),    .m_pready  (pready),    .m_pslverr (pslverr)
  );

  apb_slave_mem #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_mem (
    .pclk      (aclk),      .presetn   (aresetn),   .wait_cfg  (wait_cfg),
    .paddr     (paddr),     .pprot     (pprot),     .psel      (psel),      .penable   (penable),
    .pwrite    (pwrite),    .pwdata    (pwdata),    .pstrb     (pstrb),
    .prdata    (prdata),    .pready    (pready),    .pslverr   (pslverr)
  );

endmodule
