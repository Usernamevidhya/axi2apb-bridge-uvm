// =============================================================================
// axi2apb_bridge.sv
// AXI4-Lite slave  ->  APB4 master bridge
//
// * One transaction in flight at a time (APB is not pipelined).
// * AW and W channels are accepted independently and latched; the APB write
//   starts once both have arrived (AXI allows W before AW and vice versa).
// * Write/read arbitration: if both are pending, the one that did NOT go last
//   wins (round-robin), so neither direction can starve the other.
// * Address decode: only [APB_BASE, APB_BASE + APB_SIZE) is forwarded to APB.
//   Anything else is answered locally with DECERR (2'b11), no APB access.
// * PSLVERR from the APB slave is returned as SLVERR (2'b10).
// =============================================================================
module axi2apb_bridge #(
  parameter int          ADDR_W   = 32,
  parameter int          DATA_W   = 32,
  parameter logic [31:0] APB_BASE = 32'h0000_0000,
  parameter logic [31:0] APB_SIZE = 32'h0001_0000   // 64 KB window
)(
  input  logic                 aclk,
  input  logic                 aresetn,

  // ---------------- AXI4-Lite slave ----------------
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
  input  logic                 s_rready,

  // ---------------- APB4 master ----------------
  output logic [ADDR_W-1:0]    m_paddr,
  output logic [2:0]           m_pprot,
  output logic                 m_psel,
  output logic                 m_penable,
  output logic                 m_pwrite,
  output logic [DATA_W-1:0]    m_pwdata,
  output logic [DATA_W/8-1:0]  m_pstrb,
  input  logic [DATA_W-1:0]    m_prdata,
  input  logic                 m_pready,
  input  logic                 m_pslverr
);

  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;
  localparam logic [1:0] RESP_DECERR = 2'b11;

  // FSM state encoding
  localparam logic [2:0] S_IDLE   = 3'd0;
  localparam logic [2:0] S_SETUP  = 3'd1;  // APB setup  : PSEL=1, PENABLE=0
  localparam logic [2:0] S_ACCESS = 3'd2;  // APB access : PSEL=1, PENABLE=1
  localparam logic [2:0] S_WRESP  = 3'd3;  // drive B channel
  localparam logic [2:0] S_RRESP  = 3'd4;  // drive R channel

  // ---------------------------------------------------------------------------
  // Channel holding registers ("skid" of depth 1 per channel)
  // ---------------------------------------------------------------------------
  logic                aw_full, w_full, ar_full;
  logic [ADDR_W-1:0]   aw_addr, ar_addr;
  logic [2:0]          aw_prot, ar_prot;
  logic [DATA_W-1:0]   w_data;
  logic [DATA_W/8-1:0] w_strb;

  logic [2:0] state;
  logic       cur_write;   // type of the transaction being served
  logic       last_write;  // arbitration memory: 1 = last served was a write

  wire wr_pending = aw_full & w_full;
  wire rd_pending = ar_full;

  // Round-robin when both pending
  wire pick_write = wr_pending & (~rd_pending | ~last_write);
  wire pick_read  = rd_pending & (~wr_pending |  last_write);

  // Address window check (subtract first, so no overflow at the top of memory).
  // With APB_BASE = 0 the first compare is always true; that is expected.
  /* verilator lint_off UNSIGNED */
  wire aw_in_win = (aw_addr >= APB_BASE) && ((aw_addr - APB_BASE) < APB_SIZE);
  wire ar_in_win = (ar_addr >= APB_BASE) && ((ar_addr - APB_BASE) < APB_SIZE);
  /* verilator lint_on UNSIGNED */

  // A channel is ready whenever its holding register is empty
  assign s_awready = ~aw_full;
  assign s_wready  = ~w_full;
  assign s_arready = ~ar_full;

  // APB control comes straight from the state
  assign m_psel    = (state == S_SETUP) || (state == S_ACCESS);
  assign m_penable = (state == S_ACCESS);

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      aw_full    <= 1'b0;  w_full  <= 1'b0;  ar_full <= 1'b0;
      aw_addr    <= '0;    aw_prot <= '0;
      ar_addr    <= '0;    ar_prot <= '0;
      w_data     <= '0;    w_strb  <= '0;
      state      <= S_IDLE;
      cur_write  <= 1'b0;
      last_write <= 1'b0;
      m_paddr    <= '0;  m_pprot <= '0;  m_pwrite <= 1'b0;
      m_pwdata   <= '0;  m_pstrb <= '0;
      s_bvalid   <= 1'b0; s_bresp <= RESP_OKAY;
      s_rvalid   <= 1'b0; s_rresp <= RESP_OKAY; s_rdata <= '0;
    end else begin
      // ---------------- capture incoming channels ----------------
      if (s_awvalid && s_awready) begin
        aw_full <= 1'b1; aw_addr <= s_awaddr; aw_prot <= s_awprot;
      end
      if (s_wvalid && s_wready) begin
        w_full  <= 1'b1; w_data  <= s_wdata;  w_strb  <= s_wstrb;
      end
      if (s_arvalid && s_arready) begin
        ar_full <= 1'b1; ar_addr <= s_araddr; ar_prot <= s_arprot;
      end

      // ---------------- main FSM ----------------
      case (state)
        S_IDLE: begin
          if (pick_write) begin
            cur_write  <= 1'b1;
            last_write <= 1'b1;
            if (aw_in_win) begin
              m_paddr  <= aw_addr - APB_BASE;
              m_pprot  <= aw_prot;
              m_pwrite <= 1'b1;
              m_pwdata <= w_data;
              m_pstrb  <= w_strb;
              state    <= S_SETUP;
            end else begin
              s_bresp  <= RESP_DECERR;       // answered locally, no APB access
              s_bvalid <= 1'b1;
              state    <= S_WRESP;
            end
          end else if (pick_read) begin
            cur_write  <= 1'b0;
            last_write <= 1'b0;
            if (ar_in_win) begin
              m_paddr  <= ar_addr - APB_BASE;
              m_pprot  <= ar_prot;
              m_pwrite <= 1'b0;
              m_pstrb  <= '0;                // APB4: PSTRB must be 0 on reads
              state    <= S_SETUP;
            end else begin
              s_rresp  <= RESP_DECERR;
              s_rdata  <= '0;
              s_rvalid <= 1'b1;
              state    <= S_RRESP;
            end
          end
        end

        S_SETUP: state <= S_ACCESS;

        S_ACCESS: begin
          if (m_pready) begin
            if (cur_write) begin
              s_bresp  <= m_pslverr ? RESP_SLVERR : RESP_OKAY;
              s_bvalid <= 1'b1;
              state    <= S_WRESP;
            end else begin
              s_rresp  <= m_pslverr ? RESP_SLVERR : RESP_OKAY;
              s_rdata  <= m_prdata;
              s_rvalid <= 1'b1;
              state    <= S_RRESP;
            end
          end
        end

        S_WRESP: begin
          if (s_bready) begin
            s_bvalid <= 1'b0;
            aw_full  <= 1'b0;               // free both write holding registers
            w_full   <= 1'b0;
            state    <= S_IDLE;
          end
        end

        S_RRESP: begin
          if (s_rready) begin
            s_rvalid <= 1'b0;
            ar_full  <= 1'b0;
            state    <= S_IDLE;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
