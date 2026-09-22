// =============================================================================
// apb_slave_mem.sv
// APB4 slave: word-addressed memory with byte strobes and configurable
// wait states. This is the target that sits behind the bridge.
//
// * wait_cfg = number of cycles PREADY stays low in the access phase
//   (0 = zero-wait-state slave). It is an input so a testbench can change it
//   between transactions.
// * Accesses at or beyond DEPTH words return PSLVERR (write is dropped,
//   read data is 0).
// =============================================================================
module apb_slave_mem #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int DEPTH  = 256              // 256 words = 1 KB for 32-bit data
)(
  input  logic                 pclk,
  input  logic                 presetn,
  input  logic [3:0]           wait_cfg,
  input  logic [ADDR_W-1:0]    paddr,
  input  logic [2:0]           pprot,
  input  logic                 psel,
  input  logic                 penable,
  input  logic                 pwrite,
  input  logic [DATA_W-1:0]    pwdata,
  input  logic [DATA_W/8-1:0]  pstrb,
  output logic [DATA_W-1:0]    prdata,
  output logic                 pready,
  output logic                 pslverr
);

  localparam int BYTES = DATA_W/8;
  localparam int OFF_W = $clog2(BYTES);   // byte-offset bits (2 for 32-bit)
  localparam int IDX_W = $clog2(DEPTH);

  logic [DATA_W-1:0] mem [0:DEPTH-1];
  logic [3:0]        wait_cnt;

  wire [ADDR_W-1:0] word_addr = paddr >> OFF_W;
  wire              oob       = (word_addr >= DEPTH);
  wire [IDX_W-1:0]  idx       = word_addr[IDX_W-1:0];
  wire              access    = psel & penable;

  // PREADY rises once the access phase has lasted wait_cfg extra cycles
  assign pready  = access && (wait_cnt >= wait_cfg);
  assign pslverr = pready && oob;
  assign prdata  = (pready && !pwrite && !oob) ? mem[idx] : '0;

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn)
      wait_cnt <= '0;
    else if (access && !pready)
      wait_cnt <= wait_cnt + 1'b1;
    else
      wait_cnt <= '0;
  end

  // Memory array has no reset (like real SRAM); it is initialised to 0 for
  // simulation so reads of never-written locations are deterministic.
  initial for (int k = 0; k < DEPTH; k++) mem[k] = '0;

  always @(posedge pclk) begin
    if (pready && pwrite && !oob) begin
      for (int b = 0; b < BYTES; b++)
        if (pstrb[b]) mem[idx][8*b +: 8] <= pwdata[8*b +: 8];
    end
  end

endmodule
