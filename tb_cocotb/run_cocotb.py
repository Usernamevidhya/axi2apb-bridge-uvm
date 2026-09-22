"""Run the cocotb regression with Icarus Verilog:  python run_cocotb.py"""
from pathlib import Path
from cocotb_tools.runner import get_runner

HERE = Path(__file__).resolve().parent
RTL = HERE.parent / "rtl"


def main():
    runner = get_runner("icarus")
    runner.build(
        sources=[RTL / "axi2apb_bridge.sv", RTL / "apb_slave_mem.sv", RTL / "axi2apb_top.sv"],
        hdl_toplevel="axi2apb_top",
        build_args=["-g2012"],
        waves=True,
        always=True,
        timescale=("1ns", "1ps"),
        build_dir=HERE / "sim_build",
    )
    runner.test(
        hdl_toplevel="axi2apb_top",
        test_module="test_axi2apb",
        test_dir=HERE,
        waves=True,
    )


if __name__ == "__main__":
    main()
