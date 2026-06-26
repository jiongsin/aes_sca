# AES SCA

ASIC design workspace for AES hardware variants, including baseline, optimized, and side-channel-resilient implementations. The repository contains RTL, SystemVerilog testbenches, synthesis scripts, place-and-route scripts, power simulation support, and TVLA analysis utilities.

## Repository Layout

- `rtl/` - Verilog RTL for AES S-box, AES round operation, CTR mode, PRNG masking support, and the AHB-Lite DMA wrapper.
- `verif/tb/` - SystemVerilog testbenches, reusable verification packages, the AES interface, and the C++ reference model.
- `syn/scripts/` - Design Compiler and PrimeTime synthesis, power simulation, constraints, library setup, and report parsing scripts.
- `pnr/scripts/` - ICC2 place-and-route flow, export, timing, power simulation, library setup, and PPA reporting scripts.
- `Makefile` - Top-level automation for simulation, synthesis, gate-level simulation, P&R, static timing, power simulation, and TVLA runs.

## Supported AES Variants

- `base` - Table-based/reference-oriented AES implementation.
- `opt` - Composite-field optimized S-box and operation path.
- `sca` - Masked side-channel-resilient implementation using shared randomness.

The Makefile uses `DESIGN`, `VER`, and `MODE` to select the design variant and AES key size.

## Prerequisites

Set up the EDA environment before running the flow:

- Synopsys VCS
- Synopsys Verdi
- Synopsys Design Compiler
- Synopsys PrimeTime / PrimeTime PX
- Synopsys ICC2
- Python 3
- Python packages used by the TVLA and PPA scripts, such as NumPy, SciPy, and Matplotlib
- SAED library files for the selected technology node

The flow expects `WORKAREA` to point at the repository root:

```sh
export WORKAREA=/path/to/aes_sca
```

## Common Variables

- `DESIGN` - Top-level design family, such as `aes_sbox`, `aes_operation`, `aes_ctr`, or `aes_ahb_lite_dma`.
- `VER` - Design version, such as `base`, `opt`, or `sca`.
- `MODE` - AES key size: `128`, `192`, or `256`.
- `PERIOD` - Clock period in nanoseconds. Default: `10.0`.
- `LIBV` - Library node selector, such as `32` or `14`.
- `TEST_CNT` - Number of test encryptions. Default: `100`.
- `TVLA` - Power-analysis mode: `none`, `static`, or `dynamic`.

## Typical Flow

Prepare technology setup files:

```sh
make libv LIBV=32
```

Run RTL simulation:

```sh
make sim DESIGN=aes_operation VER=sca MODE=128
```

Run synthesis:

```sh
make syn DESIGN=aes_operation VER=sca MODE=128 PERIOD=10.0
```

Run gate-level simulation after synthesis:

```sh
make syn.sim DESIGN=aes_operation VER=sca MODE=128 PERIOD=10.0
```

Run place and route:

```sh
make pnr DESIGN=aes_operation VER=sca MODE=128 PERIOD=10.0
```

Run post-layout simulation:

```sh
make pnr.sim DESIGN=aes_operation VER=sca MODE=128 PERIOD=10.0
```

Run static timing analysis:

```sh
make sta DESIGN=aes_operation VER=sca MODE=128 PERIOD=10.0
```

## Power and TVLA

Power simulation can be run after synthesis or place-and-route:

```sh
make syn.psim DESIGN=aes_operation VER=sca MODE=128 TVLA=static
make syn.psim DESIGN=aes_operation VER=sca MODE=128 TVLA=dynamic
make pnr.psim DESIGN=aes_operation VER=sca MODE=128 TVLA=static
make pnr.psim DESIGN=aes_operation VER=sca MODE=128 TVLA=dynamic
```

TVLA analysis scripts consume generated trace chunks from the static and dynamic power runs:

```sh
make syn.tvla DESIGN=aes_operation VER=sca MODE=128
make pnr.tvla DESIGN=aes_operation VER=sca MODE=128
```

The `ppa_report.py` scripts summarize timing, area, and power reports into a compact overview report.

## Notes

- Keep `rtl/filelist.f` and `verif/tb/filelist.f` aligned with any added or removed RTL and testbench files.
- The SCA datapath relies on fresh random input for masked operation; simulation and integration should ensure the TRNG seed path is driven intentionally.
- The AHB-Lite DMA wrapper exposes FIFO status, burst control, IRQ status, key, nonce, and TRNG seed registers for software-driven operation.
