"""
cocotb regression for axi2apb_top.

Mirrors the UVM environment in Python:
  * AXI4-Lite master driver with random VALID delays and random AW/W order
  * random BREADY / RREADY backpressure
  * Python reference model (the "scoreboard")
  * random APB wait states, out-of-range (SLVERR) and out-of-window (DECERR)
    addresses, and reads and writes issued concurrently
"""
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Lock, ReadOnly, RisingEdge

OKAY, SLVERR, DECERR = 0, 2, 3
MEM_WORDS = 256                 # must match apb_slave_mem DEPTH
APB_WINDOW = 0x1_0000           # must match bridge APB_SIZE
SEED = 12345


# ----------------------------------------------------------------------------
# Reference model
# ----------------------------------------------------------------------------
class RefModel:
    def __init__(self):
        self.mem = [0] * MEM_WORDS

    @staticmethod
    def expected_resp(addr):
        if addr >= APB_WINDOW:
            return DECERR
        if (addr >> 2) >= MEM_WORDS:
            return SLVERR
        return OKAY

    def write(self, addr, data, strb):
        resp = self.expected_resp(addr)
        if resp == OKAY:
            idx = addr >> 2
            word = self.mem[idx]
            for b in range(4):
                if (strb >> b) & 1:
                    mask = 0xFF << (8 * b)
                    word = (word & ~mask) | (data & mask)
            self.mem[idx] = word
        return resp

    def read(self, addr):
        resp = self.expected_resp(addr)
        data = self.mem[addr >> 2] if resp == OKAY else 0
        return resp, data


# ----------------------------------------------------------------------------
# AXI4-Lite master helpers
# ----------------------------------------------------------------------------
async def reset(dut):
    for sig in ("s_awvalid", "s_wvalid", "s_arvalid", "s_bready", "s_rready"):
        getattr(dut, sig).value = 0
    for sig in ("s_awaddr", "s_awprot", "s_wdata", "s_wstrb", "s_araddr", "s_arprot"):
        getattr(dut, sig).value = 0
    dut.wait_cfg.value = 0
    dut.aresetn.value = 0
    await ClockCycles(dut.aclk, 5)
    dut.aresetn.value = 1
    await RisingEdge(dut.aclk)


async def send_channel(dut, valid, ready, fields, rng):
    """Drive one VALID/READY handshake. fields = {signal_name: value}.

    READY is sampled just before the clock edge (in the ReadOnly phase of the
    current cycle), which is exactly what the DUT sees at that edge.
    """
    for _ in range(rng.randint(0, 3)):            # random start delay
        await RisingEdge(dut.aclk)
    for name, val in fields.items():
        getattr(dut, name).value = val
    getattr(dut, valid).value = 1
    while True:
        await ReadOnly()
        handshake = bool(int(getattr(dut, ready).value))
        await RisingEdge(dut.aclk)
        if handshake:
            break
    getattr(dut, valid).value = 0


async def recv_channel(dut, valid, ready, capture, rng):
    """Accept one B or R beat with random READY backpressure.

    capture = list of signal names to return, sampled at the handshake edge.
    """
    while True:
        getattr(dut, ready).value = 1 if rng.random() < 0.6 else 0
        await ReadOnly()
        handshake = bool(int(getattr(dut, valid).value)) and bool(int(getattr(dut, ready).value))
        values = [int(getattr(dut, n).value) for n in capture] if handshake else None
        await RisingEdge(dut.aclk)
        if handshake:
            getattr(dut, ready).value = 0
            return values


class AxiLiteMaster:
    def __init__(self, dut, rng):
        self.dut, self.rng = dut, rng
        self.wlock = Lock()
        self.rlock = Lock()

    async def write(self, addr, data, strb=0xF):
        dut, rng = self.dut, self.rng
        async with self.wlock:
            aw = cocotb.start_soon(send_channel(
                dut, "s_awvalid", "s_awready",
                {"s_awaddr": addr, "s_awprot": 0}, rng))
            w = cocotb.start_soon(send_channel(
                dut, "s_wvalid", "s_wready",
                {"s_wdata": data, "s_wstrb": strb}, rng))
            await aw
            await w
            (resp,) = await recv_channel(dut, "s_bvalid", "s_bready", ["s_bresp"], rng)
            return resp

    async def read(self, addr):
        dut, rng = self.dut, self.rng
        async with self.rlock:
            await send_channel(dut, "s_arvalid", "s_arready",
                               {"s_araddr": addr, "s_arprot": 0}, rng)
            resp, data = await recv_channel(dut, "s_rvalid", "s_rready",
                                            ["s_rresp", "s_rdata"], rng)
            return resp, data


def random_addr(rng):
    r = rng.random()
    if r < 0.80:
        return rng.randrange(0, MEM_WORDS) * 4                  # valid memory
    if r < 0.90:
        return rng.randrange(MEM_WORDS, APB_WINDOW // 4) * 4    # SLVERR
    return rng.randrange(APB_WINDOW // 4, 0x4000_0000) * 4      # DECERR


# ----------------------------------------------------------------------------
# Tests
# ----------------------------------------------------------------------------
@cocotb.test()
async def test_directed_smoke(dut):
    """A few hand-written transactions, easy to follow in the waveform."""
    cocotb.start_soon(Clock(dut.aclk, 10, unit="ns").start())
    await reset(dut)
    rng = random.Random(SEED)
    m = AxiLiteMaster(dut, rng)

    assert await m.write(0x10, 0xDEADBEEF) == OKAY
    assert await m.read(0x10) == (OKAY, 0xDEADBEEF)

    assert await m.write(0x10, 0x0000_00AA, strb=0b0001) == OKAY   # byte write
    assert await m.read(0x10) == (OKAY, 0xDEADBEAA)

    dut.wait_cfg.value = 5                                          # slow slave
    assert await m.write(0x20, 0x12345678) == OKAY
    assert await m.read(0x20) == (OKAY, 0x12345678)

    assert await m.write(0x400, 1) == SLVERR                        # beyond memory
    assert (await m.read(0x400))[0] == SLVERR
    assert await m.write(0x2_0000, 1) == DECERR                     # outside window
    assert await m.read(0x2_0000) == (DECERR, 0)


@cocotb.test()
async def test_random_concurrent(dut):
    """Constrained-random reads and writes in parallel, checked by the model."""
    cocotb.start_soon(Clock(dut.aclk, 10, unit="ns").start())
    await reset(dut)
    rng = random.Random(SEED + 1)
    m = AxiLiteMaster(dut, rng)
    model = RefModel()
    n_ops = 400
    stats = {"write": 0, "read": 0, OKAY: 0, SLVERR: 0, DECERR: 0}

    # Memory is not cleared by reset (like real SRAM) and an earlier test may
    # have written to it, so bring DUT and model into a known state first.
    for idx in range(MEM_WORDS):
        assert await m.write(idx * 4, 0) == OKAY

    # To keep the model exact while reads and writes run in parallel, each
    # pair uses a read address that differs from the write address in flight.
    async def writer(addr, data, strb):
        exp = model.write(addr, data, strb)
        got = await m.write(addr, data, strb)
        assert got == exp, f"WRITE {addr:#x}: bresp {got} expected {exp}"
        stats["write"] += 1
        stats[got] += 1

    async def reader(addr):
        exp = model.read(addr)
        got = await m.read(addr)
        assert got == exp, f"READ {addr:#x}: got {got} expected {exp}"
        stats["read"] += 1
        stats[got[0]] += 1

    for i in range(n_ops // 2):
        if i % 25 == 0:
            dut.wait_cfg.value = rng.randint(0, 7)
        waddr = random_addr(rng)
        raddr = random_addr(rng)
        while raddr == waddr:
            raddr = random_addr(rng)
        wt = cocotb.start_soon(writer(waddr, rng.getrandbits(32), rng.randint(1, 15)))
        rt = cocotb.start_soon(reader(raddr))
        await wt
        await rt

    dut._log.info("Coverage-style summary: %s", stats)
    assert stats[OKAY] > 0 and stats[SLVERR] > 0 and stats[DECERR] > 0
