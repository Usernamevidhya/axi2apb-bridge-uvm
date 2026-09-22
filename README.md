# AXI4-Lite to APB4 Bridge — RTL + UVM Verification

An AXI4-Lite slave to APB4 master bridge in SystemVerilog, an APB memory slave with configurable wait states, a class-based UVM environment with SVA protocol checkers and functional coverage, and a cocotb regression that mirrors it. The design is synthesised and implemented for a Zynq-7000 (XC7Z007S) in Vivado.

![cocotb-regression](../../actions/workflows/cocotb.yml/badge.svg)

---

## 1. What problem does this solve?

Inside an SoC, the CPU talks to memory over a **fast** bus (AXI), while slow peripherals like UART, GPIO and timers sit on a **simple, low-power** bus (APB). A **bridge** translates between them. The CPU issues an AXI transaction, and the bridge turns it into the APB sequence the peripheral understands, then carries the response back.

```
            AXI4-Lite                        APB4
  CPU / TB ───────────►  axi2apb_bridge  ───────────►  apb_slave_mem
           ◄───────────                  ◄───────────  (wait states,
             B / R resp                   PREADY/PSLVERR  PSLVERR)
```

## 2. The two protocols in one minute

**AXI4-Lite** has five independent channels: AW (write address), W (write data), B (write response), AR (read address) and R (read data). Every channel uses the same **VALID/READY handshake**. The sender raises VALID and holds its data steady, the receiver raises READY when it can accept, and the transfer happens on the clock edge where **both are high**. Because the channels are independent, W can arrive before AW, and the bridge must handle that.

**APB4** is much simpler and not pipelined. Every transfer has two phases:

| Phase  | PSEL | PENABLE | Lasts |
|--------|------|---------|-------|
| Setup  | 1    | 0       | exactly 1 cycle |
| Access | 1    | 1       | until the slave raises PREADY (extra cycles = **wait states**) |

The slave can flag an error with **PSLVERR** in the final access cycle.

**Response codes returned on AXI:** OKAY (`00`), SLVERR (`10`) when the APB slave reported an error, and DECERR (`11`) when the address is outside the bridge window, so no APB access happens at all.

## 3. Design (`rtl/`)

| File | What it does |
|------|--------------|
| `axi2apb_bridge.sv` | 5-state FSM: `IDLE → SETUP → ACCESS → WRESP/RRESP`. One holding register per AXI channel, round-robin arbitration between pending reads and writes, and address decode producing DECERR. |
| `apb_slave_mem.sv`  | 256 × 32-bit memory with byte strobes (PSTRB), `wait_cfg` wait states, and PSLVERR for out-of-range addresses. |
| `axi2apb_top.sv`    | Bridge + memory. This is the DUT for every testbench. |

**Key design decisions** (the "why" questions interviewers ask):
- **Why holding registers?** AW and W arrive independently. Latching each one lets the bridge accept both in any order and start APB only when it has both.
- **Why round-robin?** If reads always won, a stream of reads could starve writes forever. Alternating fixes that.
- **Why is PADDR registered?** APB requires the address and control signals to stay stable for the whole transfer, including wait states. Registered outputs guarantee that.

## 4. Verification

### UVM environment (`tb_uvm/`) — runs in Vivado xsim

```
test ─ env ─┬─ agent ─┬─ sequencer ──► driver ──► virtual interface ──► DUT
            │         └─ monitor ◄──────────────── virtual interface
            ├─ scoreboard ◄── monitor   (reference model checks every transaction)
            └─ coverage   ◄── monitor   (functional coverage)
```

| Component | Role |
|-----------|------|
| **Sequence item** | One read or write, with *constrained-random* address region, data, strobes, wait states, VALID delays and READY backpressure. |
| **Sequences** | `smoke_seq` (directed), `write_read_seq` (write then read back), `random_seq` (fully random). |
| **Driver** | Converts items into pin activity. Drives AW and W in parallel with random delays. |
| **Monitor** | Watches the pins and rebuilds transactions **independently of the driver**, so a driver bug can't hide a DUT bug. |
| **Scoreboard** | A software model of the bridge and memory. Every observed transaction is checked against it. |
| **Coverage** | Covergroup on kind × response × wait states × strobe pattern. It answers "did we actually test it?" |
| **Virtual interface** | How class-based code (which can't touch module pins) reaches the DUT. Clocking blocks avoid races. |

### SVA protocol checkers (`sva/`)
Attached with `bind`, so the RTL is untouched. The checks include:
- VALID stays high with stable payload until READY, on all five AXI channels.
- APB setup lasts exactly one cycle and is always followed by access.
- APB signals stay frozen during wait states.
- PSTRB is zero on reads, and PSLVERR appears only in the completing cycle.

Cover properties confirm that wait states, errors, backpressure and W-before-AW actually occurred.

### cocotb regression (`tb_cocotb/`) — runs with Icarus Verilog
The same ideas in Python: a random AXI master, a reference model, random wait states, and error addresses, with **reads and writes issued concurrently**. The GitHub Actions workflow runs it on every push.

## 5. How to run

### Option A: Vivado only (nothing else to install)
Open Vivado, then open the **Tcl Console** at the bottom of the window. Use forward slashes in paths, even on Windows.
```tcl
cd C:/path/to/axi2apb-bridge-uvm
source scripts/sim_uvm.tcl                               ;# smoke_test
set test random_test ; source scripts/sim_uvm.tcl       ;# constrained-random
set test random_test ; set seed 42 ; source scripts/sim_uvm.tcl
```
Look for `Scoreboard: N passed, 0 failed`, `Functional coverage = X%`, `UVM_ERROR : 0`, and no SVA `$error` lines.

Synthesis and implementation for the Zynq-7000 XC7Z007S (close any open project first):
```tcl
source C:/path/to/axi2apb-bridge-uvm/scripts/synth.tcl
```
Reports go to `build/vivado/`. A positive WNS in `timing_summary.rpt` means the 100 MHz target was met.

### Option B: command line (PowerShell, Vivado bin on PATH)
```powershell
.\scripts\run_uvm.ps1 -Test random_test -Seed 42
.\scripts\run_synth.ps1
```

### cocotb regression (Icarus Verilog + Python)
This runs automatically on GitHub Actions on every push. To run it locally:
```powershell
pip install -r tb_cocotb/requirements.txt
cd tb_cocotb
python run_cocotb.py
```

## 6. Results

*Fill these in from your own runs.*

| Item | Result |
|------|--------|
| cocotb regression | |
| UVM `smoke_test` scoreboard | |
| UVM `random_test` scoreboard / coverage | |
| SVA failures | |
| Post-route utilization (LUT / FF / LUTRAM) | |
| WNS at 100 MHz | |

## 7. Repository layout
```
rtl/          bridge, APB memory slave, top
sva/          protocol assertions (bind)
tb_uvm/       UVM interface, package (item → tests), top
tb_cocotb/    cocotb test + runner
constraints/  out-of-context clock constraint
scripts/      xsim + Vivado batch scripts (PowerShell / Tcl)
```
