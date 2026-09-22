// =============================================================================
// axi2apb_pkg.sv -- the complete UVM environment in one package.
//
//   test
//    └─ env
//        ├─ agent ── sequencer ─► driver ─► (virtual interface) ─► DUT
//        │            monitor  ◄──────────  (virtual interface)
//        ├─ scoreboard  ◄── monitor.ap   (reference model, checks every txn)
//        └─ coverage    ◄── monitor.ap   (functional coverage)
// =============================================================================
package axi2apb_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam int unsigned MEM_WORDS  = 256;          // apb_slave_mem DEPTH
  localparam int unsigned MEM_BYTES  = MEM_WORDS * 4;
  localparam int unsigned APB_WINDOW = 32'h0001_0000; // bridge APB_SIZE

  localparam bit [1:0] OKAY = 2'b00, SLVERR = 2'b10, DECERR = 2'b11;

  typedef enum {REGION_MEM, REGION_SLVERR, REGION_DECERR} region_e;

  // ===========================================================================
  // Sequence item: one AXI4-Lite read or write, plus timing knobs
  // ===========================================================================
  class axi_item extends uvm_sequence_item;
    rand bit          is_write;
    rand region_e     region;
    rand bit [31:0]   addr;
    rand bit [31:0]   data;
    rand bit [3:0]    strb;
    rand bit [3:0]    wait_cfg;     // APB wait states for this transaction
    rand int unsigned aw_delay, w_delay, ar_delay;  // cycles before VALID
    rand int unsigned ready_pct;    // % chance BREADY/RREADY is high per cycle

    // filled in by driver / monitor
    bit [1:0]  resp;
    bit [31:0] rdata;

    // ---- constraints ("constrained-random") ----
    constraint c_region  { region dist {REGION_MEM := 80, REGION_SLVERR := 10, REGION_DECERR := 10}; }
    constraint c_align   { addr[1:0] == 2'b00; }
    constraint c_addr {
      region == REGION_MEM     -> addr <  MEM_BYTES;
      region == REGION_SLVERR  -> addr inside {[MEM_BYTES : APB_WINDOW - 4]};
      region == REGION_DECERR  -> addr inside {[APB_WINDOW : 32'h3FFF_FFFC]};
    }
    constraint c_strb    { strb != 4'b0000; }
    constraint c_wait    { wait_cfg dist {0 := 30, [1:3] := 40, [4:15] := 30}; }
    constraint c_delay   { aw_delay inside {[0:3]}; w_delay inside {[0:3]}; ar_delay inside {[0:3]}; }
    constraint c_ready   { ready_pct inside {[30:100]}; }

    `uvm_object_utils_begin(axi_item)
      `uvm_field_int(is_write, UVM_ALL_ON)
      `uvm_field_int(addr,     UVM_ALL_ON | UVM_HEX)
      `uvm_field_int(data,     UVM_ALL_ON | UVM_HEX)
      `uvm_field_int(strb,     UVM_ALL_ON | UVM_BIN)
      `uvm_field_int(wait_cfg, UVM_ALL_ON)
      `uvm_field_int(resp,     UVM_ALL_ON)
      `uvm_field_int(rdata,    UVM_ALL_ON | UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "axi_item");
      super.new(name);
    endfunction

    function string convert2string();
      return $sformatf("%s addr=%08h %s strb=%b wait=%0d resp=%0d",
                       is_write ? "WR" : "RD", addr,
                       is_write ? $sformatf("wdata=%08h", data) : $sformatf("rdata=%08h", rdata),
                       strb, wait_cfg, resp);
    endfunction
  endclass

  // ===========================================================================
  // Sequences
  // ===========================================================================
  class random_seq extends uvm_sequence #(axi_item);
    `uvm_object_utils(random_seq)
    int unsigned n_items = 500;
    function new(string name = "random_seq"); super.new(name); endfunction
    task body();
      repeat (n_items) begin
        axi_item it = axi_item::type_id::create("it");
        start_item(it);
        if (!it.randomize()) `uvm_fatal("RAND", "randomize failed")
        finish_item(it);
      end
    endtask
  endclass

  // Write then read back the same address, so every write gets checked
  class write_read_seq extends uvm_sequence #(axi_item);
    `uvm_object_utils(write_read_seq)
    int unsigned n_pairs = 200;
    function new(string name = "write_read_seq"); super.new(name); endfunction
    task body();
      repeat (n_pairs) begin
        axi_item wr = axi_item::type_id::create("wr");
        axi_item rd = axi_item::type_id::create("rd");
        start_item(wr);
        if (!wr.randomize() with { is_write == 1; }) `uvm_fatal("RAND", "randomize failed")
        finish_item(wr);
        start_item(rd);
        if (!rd.randomize() with { is_write == 0; addr == wr.addr; region == wr.region; })
          `uvm_fatal("RAND", "randomize failed")
        finish_item(rd);
      end
    endtask
  endclass

  // Hand-written transactions: easy to read in the waveform
  class smoke_seq extends uvm_sequence #(axi_item);
    `uvm_object_utils(smoke_seq)
    function new(string name = "smoke_seq"); super.new(name); endfunction
    task do_one(bit w, bit [31:0] a, bit [31:0] d, bit [3:0] s, bit [3:0] ws); region_e r = (a < MEM_BYTES) ? REGION_MEM : ((a < APB_WINDOW) ? REGION_SLVERR : REGION_DECERR);
      axi_item it = axi_item::type_id::create("it");
      start_item(it);
      if (!it.randomize() with { is_write == w; addr == a; data == d; strb == s;
                                 wait_cfg == ws; region == r;
                                    })
        `uvm_fatal("RAND", "randomize failed")
      finish_item(it);
    endtask
    task body();
      do_one(1, 32'h10,    32'hDEAD_BEEF, 4'hF, 0);   // full write
      do_one(0, 32'h10,    0,             4'hF, 0);   // read back
      do_one(1, 32'h10,    32'h0000_00AA, 4'h1, 0);   // byte-strobe write
      do_one(0, 32'h10,    0,             4'hF, 0);   // expect DEADBEAA
      do_one(1, 32'h20,    32'h1234_5678, 4'hF, 5);   // slow slave
      do_one(0, 32'h20,    0,             4'hF, 5);
      do_one(1, 32'h400,   32'h1,         4'hF, 0);   // SLVERR
      do_one(0, 32'h2_0000,0,             4'hF, 0);   // DECERR
    endtask
  endclass

  // ===========================================================================
  // Driver: turns items into pin wiggles (acts as the AXI4-Lite master)
  // ===========================================================================
  class axi_driver extends uvm_driver #(axi_item);
    `uvm_component_utils(axi_driver)
    virtual axi_lite_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface not set")
    endfunction

    task reset_signals();
      vif.drv_cb.awvalid <= 0; vif.drv_cb.wvalid <= 0; vif.drv_cb.arvalid <= 0;
      vif.drv_cb.bready  <= 0; vif.drv_cb.rready <= 0;
      vif.drv_cb.awaddr  <= 0; vif.drv_cb.awprot <= 0; vif.drv_cb.wdata <= 0;
      vif.drv_cb.wstrb   <= 0; vif.drv_cb.araddr <= 0; vif.drv_cb.arprot <= 0;
      vif.drv_cb.wait_cfg <= 0;
    endtask

    task run_phase(uvm_phase phase);
      reset_signals();
      @(posedge vif.aresetn);
      repeat (2) @(vif.drv_cb);
      forever begin
        seq_item_port.get_next_item(req);
        vif.drv_cb.wait_cfg <= req.wait_cfg;
        @(vif.drv_cb);
        if (req.is_write) drive_write(req);
        else              drive_read(req);
        `uvm_info("DRV", req.convert2string(), UVM_HIGH)
        seq_item_port.item_done();
      end
    endtask

    // AW and W are driven in parallel with independent random delays, so
    // W-before-AW, AW-before-W and simultaneous all get exercised.
    task drive_write(axi_item t);
      fork
        begin
          repeat (t.aw_delay) @(vif.drv_cb);
          vif.drv_cb.awaddr  <= t.addr;
          vif.drv_cb.awprot  <= 3'b000;
          vif.drv_cb.awvalid <= 1;
          do @(vif.drv_cb); while (!vif.drv_cb.awready);
          vif.drv_cb.awvalid <= 0;
        end
        begin
          repeat (t.w_delay) @(vif.drv_cb);
          vif.drv_cb.wdata  <= t.data;
          vif.drv_cb.wstrb  <= t.strb;
          vif.drv_cb.wvalid <= 1;
          do @(vif.drv_cb); while (!vif.drv_cb.wready);
          vif.drv_cb.wvalid <= 0;
        end
      join
      wait_resp(t, 1);
    endtask

    task drive_read(axi_item t);
      repeat (t.ar_delay) @(vif.drv_cb);
      vif.drv_cb.araddr  <= t.addr;
      vif.drv_cb.arprot  <= 3'b000;
      vif.drv_cb.arvalid <= 1;
      do @(vif.drv_cb); while (!vif.drv_cb.arready);
      vif.drv_cb.arvalid <= 0;
      wait_resp(t, 0);
    endtask

    // Random READY backpressure on B / R
    task wait_resp(axi_item t, bit is_b);
      bit rdy;
      forever begin
        rdy = ($urandom_range(99) < t.ready_pct);
        if (is_b) vif.drv_cb.bready <= rdy; else vif.drv_cb.rready <= rdy;
        @(vif.drv_cb);
        if (is_b && rdy && vif.drv_cb.bvalid) begin
          t.resp = vif.drv_cb.bresp;
          break;
        end
        if (!is_b && rdy && vif.drv_cb.rvalid) begin
          t.resp  = vif.drv_cb.rresp;
          t.rdata = vif.drv_cb.rdata;
          break;
        end
      end
      if (is_b) vif.drv_cb.bready <= 0; else vif.drv_cb.rready <= 0;
    endtask
  endclass

  // ===========================================================================
  // Monitor: watches the pins and rebuilds transactions independently
  // ===========================================================================
  class axi_monitor extends uvm_monitor;
    `uvm_component_utils(axi_monitor)
    virtual axi_lite_if vif;
    uvm_analysis_port #(axi_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface not set")
    endfunction

    task run_phase(uvm_phase phase);
      bit [31:0] aw_addr, w_data, ar_addr;
      bit [3:0]  w_strb;
      forever begin
        @(vif.mon_cb);
        if (!vif.aresetn) continue;
        if (vif.mon_cb.awvalid && vif.mon_cb.awready) aw_addr = vif.mon_cb.awaddr;
        if (vif.mon_cb.wvalid  && vif.mon_cb.wready)  begin
          w_data = vif.mon_cb.wdata;  w_strb = vif.mon_cb.wstrb;
        end
        if (vif.mon_cb.arvalid && vif.mon_cb.arready) ar_addr = vif.mon_cb.araddr;

        // The bridge has one transaction in flight, so a response always
        // belongs to the most recently accepted request of that type.
        if (vif.mon_cb.bvalid && vif.mon_cb.bready) begin
          axi_item t = axi_item::type_id::create("wr_obs");
          t.is_write = 1; t.addr = aw_addr; t.data = w_data; t.strb = w_strb;
          t.resp = vif.mon_cb.bresp; t.wait_cfg = vif.mon_cb.wait_cfg;
          ap.write(t);
        end
        if (vif.mon_cb.rvalid && vif.mon_cb.rready) begin
          axi_item t = axi_item::type_id::create("rd_obs");
          t.is_write = 0; t.addr = ar_addr;
          t.resp = vif.mon_cb.rresp; t.rdata = vif.mon_cb.rdata;
          t.wait_cfg = vif.mon_cb.wait_cfg;
          ap.write(t);
        end
      end
    endtask
  endclass

  // ===========================================================================
  // Agent: bundles sequencer + driver + monitor
  // ===========================================================================
  class axi_agent extends uvm_agent;
    `uvm_component_utils(axi_agent)
    uvm_sequencer #(axi_item) sqr;
    axi_driver                drv;
    axi_monitor               mon;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sqr = uvm_sequencer#(axi_item)::type_id::create("sqr", this);
      drv = axi_driver::type_id::create("drv", this);
      mon = axi_monitor::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  // ===========================================================================
  // Scoreboard: reference model of bridge + memory; checks every transaction
  // ===========================================================================
  class axi_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(axi_scoreboard)
    uvm_analysis_imp #(axi_item, axi_scoreboard) imp;

    bit [31:0]   mem [MEM_WORDS];   // starts at 0, same as the RTL memory
    int unsigned n_pass, n_fail;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      imp = new("imp", this);
    endfunction

    function bit [1:0] expected_resp(bit [31:0] a);
      if (a >= APB_WINDOW)          return DECERR;
      if ((a >> 2) >= MEM_WORDS)    return SLVERR;
      return OKAY;
    endfunction

    function void write(axi_item t);
      bit [1:0]  exp_resp = expected_resp(t.addr);
      bit [31:0] exp_data = 0;
      bit        ok;

      if (t.is_write) begin
        ok = (t.resp == exp_resp);
        if (exp_resp == OKAY)
          for (int b = 0; b < 4; b++)
            if (t.strb[b]) mem[t.addr >> 2][8*b +: 8] = t.data[8*b +: 8];
      end else begin
        if (exp_resp == OKAY) exp_data = mem[t.addr >> 2];
        ok = (t.resp == exp_resp) && (t.rdata == exp_data);
      end

      if (ok) n_pass++;
      else begin
        n_fail++;
        `uvm_error("SCB", $sformatf("MISMATCH %s | expected resp=%0d data=%08h",
                   t.convert2string(), exp_resp, exp_data))
      end
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("SCB", $sformatf("Scoreboard: %0d passed, %0d failed", n_pass, n_fail), UVM_NONE)
      if (n_pass == 0) `uvm_error("SCB", "No transactions were checked")
    endfunction
  endclass

  // ===========================================================================
  // Functional coverage: which scenarios did the random tests really hit?
  // ===========================================================================
  class axi_coverage extends uvm_subscriber #(axi_item);
    `uvm_component_utils(axi_coverage)
    axi_item t;

    covergroup cg;
      cp_kind : coverpoint t.is_write { bins read = {0}; bins write = {1}; }
      cp_resp : coverpoint t.resp     { bins okay = {OKAY}; bins slverr = {SLVERR};
                                        bins decerr = {DECERR}; illegal_bins exokay = {2'b01}; }
      cp_wait : coverpoint t.wait_cfg { bins zero = {0}; bins short_w = {[1:3]};
                                        bins long_w = {[4:15]}; }
      cp_strb : coverpoint t.strb iff (t.is_write) {
                  bins full = {4'hF};
                  bins single_byte = {4'h1, 4'h2, 4'h4, 4'h8};
                  bins partial = {4'h3, 4'h5, 4'h6, 4'h7, 4'h9, 4'hA,
                                  4'hB, 4'hC, 4'hD, 4'hE}; }
      x_kind_resp : cross cp_kind, cp_resp;
      x_kind_wait : cross cp_kind, cp_wait;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg = new();
    endfunction

    function void write(axi_item t);
      this.t = t;
      cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("COV", $sformatf("Functional coverage = %0.2f%%", cg.get_coverage()), UVM_NONE)
    endfunction
  endclass

  // ===========================================================================
  // Environment
  // ===========================================================================
  class axi2apb_env extends uvm_env;
    `uvm_component_utils(axi2apb_env)
    axi_agent      agent;
    axi_scoreboard scb;
    axi_coverage   cov;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = axi_agent::type_id::create("agent", this);
      scb   = axi_scoreboard::type_id::create("scb", this);
      cov   = axi_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      agent.mon.ap.connect(scb.imp);
      agent.mon.ap.connect(cov.analysis_export);
    endfunction
  endclass

  // ===========================================================================
  // Tests  (pick one with +UVM_TESTNAME=<name>)
  // ===========================================================================
  class base_test extends uvm_test;
    `uvm_component_utils(base_test)
    axi2apb_env env;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = axi2apb_env::type_id::create("env", this);
    endfunction
    virtual task run_seq(); endtask
    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      run_seq();
      #100ns;
      phase.drop_objection(this);
    endtask
  endclass

  class smoke_test extends base_test;
    `uvm_component_utils(smoke_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_seq();
      smoke_seq s = smoke_seq::type_id::create("s");
      s.start(env.agent.sqr);
    endtask
  endclass

  class random_test extends base_test;
    `uvm_component_utils(random_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_seq();
      write_read_seq wr = write_read_seq::type_id::create("wr");
      random_seq     rs = random_seq::type_id::create("rs");
      wr.start(env.agent.sqr);
      rs.start(env.agent.sqr);
    endtask
  endclass

endpackage
