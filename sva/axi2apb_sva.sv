// =============================================================================
// axi2apb_sva.sv
// Protocol checkers for both sides of the bridge, attached with `bind` so the
// RTL itself stays untouched. Used in the UVM (Vivado xsim) simulation.
//
// Each property reads as "if <antecedent> then <consequent>":
//   |->  consequent checked in the SAME cycle
//   |=>  consequent checked in the NEXT cycle
// =============================================================================
module axi2apb_sva (
  input logic        aclk,
  input logic        aresetn,
  // AXI4-Lite
  input logic [31:0] s_awaddr,  input logic s_awvalid, input logic s_awready,
  input logic [31:0] s_wdata,   input logic [3:0] s_wstrb,
  input logic        s_wvalid,  input logic s_wready,
  input logic [1:0]  s_bresp,   input logic s_bvalid,  input logic s_bready,
  input logic [31:0] s_araddr,  input logic s_arvalid, input logic s_arready,
  input logic [31:0] s_rdata,   input logic [1:0] s_rresp,
  input logic        s_rvalid,  input logic s_rready,
  // APB4
  input logic [31:0] paddr,     input logic psel,      input logic penable,
  input logic        pwrite,    input logic [31:0] pwdata, input logic [3:0] pstrb,
  input logic        pready,    input logic pslverr
);

  
  

  // ---------------------------------------------------------------------------
  // AXI4-Lite rule: once VALID is high it must stay high, with stable payload,
  // until READY. (Checked on the signals the bridge DRIVES: B and R.)
  // The same rule for AW/W/AR checks the testbench (the master) is legal.
  // ---------------------------------------------------------------------------
  a_aw_stable: assert property (@(posedge aclk) disable iff (!aresetn) s_awvalid && !s_awready |=> s_awvalid && $stable(s_awaddr))
    else $error("AXI: AWVALID dropped or AWADDR changed before AWREADY");
  a_w_stable:  assert property (@(posedge aclk) disable iff (!aresetn) s_wvalid && !s_wready |=> s_wvalid && $stable(s_wdata) && $stable(s_wstrb))
    else $error("AXI: WVALID dropped or W payload changed before WREADY");
  a_ar_stable: assert property (@(posedge aclk) disable iff (!aresetn) s_arvalid && !s_arready |=> s_arvalid && $stable(s_araddr))
    else $error("AXI: ARVALID dropped or ARADDR changed before ARREADY");
  a_b_stable:  assert property (@(posedge aclk) disable iff (!aresetn) s_bvalid && !s_bready |=> s_bvalid && $stable(s_bresp))
    else $error("AXI: BVALID dropped or BRESP changed before BREADY");
  a_r_stable:  assert property (@(posedge aclk) disable iff (!aresetn) s_rvalid && !s_rready |=> s_rvalid && $stable(s_rdata) && $stable(s_rresp))
    else $error("AXI: RVALID dropped or R payload changed before RREADY");

  // Bridge serves one transaction at a time, so B and R never overlap
  a_one_resp:  assert property (@(posedge aclk) disable iff (!aresetn) !(s_bvalid && s_rvalid))
    else $error("BRIDGE: BVALID and RVALID high together");

  // AXI4-Lite has no EXOKAY (2'b01)
  a_no_exokay: assert property (@(posedge aclk) disable iff (!aresetn) s_bvalid |-> s_bresp != 2'b01)
    else $error("AXI: EXOKAY is illegal on AXI4-Lite");

  // ---------------------------------------------------------------------------
  // APB4 rules
  // ---------------------------------------------------------------------------
  // Setup phase (PSEL=1, PENABLE=0) lasts exactly one cycle, then access
  a_apb_setup_to_access: assert property (@(posedge aclk) disable iff (!aresetn) psel && !penable |=> psel && penable)
    else $error("APB: setup phase not followed by access phase");

  // PENABLE only ever rises after a setup phase
  a_apb_enable_after_setup: assert property (@(posedge aclk) disable iff (!aresetn) $rose(penable) |-> $past(psel && !penable))
    else $error("APB: PENABLE rose without a setup phase");

  // PENABLE never without PSEL
  a_apb_enable_needs_sel: assert property (@(posedge aclk) disable iff (!aresetn) penable |-> psel)
    else $error("APB: PENABLE high while PSEL low");

  // While the slave inserts wait states, everything the master drives is frozen
  a_apb_stable_in_wait: assert property (@(posedge aclk) disable iff (!aresetn) 
      psel && penable && !pready |=>
      psel && penable && $stable(paddr) && $stable(pwrite) &&
      $stable(pwdata) && $stable(pstrb))
    else $error("APB: master changed signals during a wait state");

  // APB4: PSTRB must be all-zero on reads
  a_apb_read_strb_zero: assert property (@(posedge aclk) disable iff (!aresetn) psel && !pwrite |-> pstrb == '0)
    else $error("APB: PSTRB not zero on a read");

  // PSLVERR is only meaningful in the last cycle of an access
  a_apb_slverr_timing: assert property (@(posedge aclk) disable iff (!aresetn) pslverr |-> psel && penable && pready)
    else $error("APB: PSLVERR outside the completing access cycle");

  // No X on control after reset
  a_no_x_ctrl: assert property (@(posedge aclk) disable iff (!aresetn) !$isunknown({psel, penable, s_bvalid, s_rvalid,
                                             s_awready, s_wready, s_arready}))
    else $error("X on a control signal");

  // ---------------------------------------------------------------------------
  // Cover points: proof that interesting scenarios actually happened
  // ---------------------------------------------------------------------------
  c_apb_wait_state:   cover property (@(posedge aclk) disable iff (!aresetn) psel && penable && !pready);
  c_apb_zero_wait:    cover property (@(posedge aclk) disable iff (!aresetn) psel && !penable ##1 psel && penable && pready);
  c_apb_slverr:       cover property (@(posedge aclk) disable iff (!aresetn) pslverr);
  c_axi_decerr_write: cover property (@(posedge aclk) disable iff (!aresetn) s_bvalid && s_bready && s_bresp == 2'b11);
  c_axi_w_before_aw:  cover property (@(posedge aclk) disable iff (!aresetn) s_wvalid && !s_awvalid);
  c_b_backpressure:   cover property (@(posedge aclk) disable iff (!aresetn) s_bvalid && !s_bready);
  c_r_backpressure:   cover property (@(posedge aclk) disable iff (!aresetn) s_rvalid && !s_rready);

endmodule

// The `bind` that attaches this checker to the DUT lives in tb_uvm/tb_top.sv
