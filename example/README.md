# DCMAC Reusable Vivado block design

Example Vivado project that exercises the `dcmac` hierarchy on the AMD Versal V80.
Creates the project, adds every HDL/XDC file shipped in the package,
runs `bd_dcmac` to build the block design, generates the wrapper, and sets
it as top.

## Prerequisites

- Vivado **2025.1** or newer

## Usage

```
make                    # build with defaults
make DUAL=1 AXIL=1      # any combination of the knobs in the table below
make clean              # wipe build/ and vivado logs
```

Or call the TCL directly:

```
vivado -mode batch -source create_dcmac_example.tcl \
       -tclargs <dcmac_index> <dual_dcmac> <dcmac_axil> <wrap_qsfp> <board> <nclk_f> <dynamic_rate>
```

Project name is fixed to `dcmac_example` (project lands in `build/dcmac_example/`). All `-tclargs` and Makefile vars are optional.

## Parameters

| Make var    | tclarg / proc param | Default | Meaning |
|---|---|---|---|
| `INDEX`     | `dcmac_index` | `0`   | Selects which DCMAC site to use; resolved via `(board, dcmac_index)` lookup in `tcl/board_config.tcl`. For V80: `0` → `DCMAC_X1Y1`, `1` → `DCMAC_X0Y2`. |
| `DUAL`      | `dual_dcmac`  | `0`   | `0` → single QSFP56, `1` → dual QSFP56 (two GT quads). |
| `AXIL`      | `dcmac_axil`  | `0`   | `0` → AXI4-Lite tied off, `1` → expose `s_axi` top-level port. Clock + reset shared with `aclk`/`aresetn` (no separate `s_axi_aclk`/`s_axi_aresetn`). |
| `WRAP_QSFP` | `wrap_qsfp`   | `0`   | `0` → call `bd_dcmac` (flat top); `1` → call `bd_dcmac_qsfp`, which builds inside a `qsfp_${2i}_n_${2i+1}` hier. |
| `BOARD`     | `board`       | `v80` | Board key for the per-board DCMAC site dict in `tcl/board_config.tcl`. Only `v80` is defined today. |
| `NCLK_F`    | `nclk_f`      | `391` | DCMAC AXIS clock in MHz; sets `cfg(nclk_f)` consumed by `dcmac.tcl`. |
| `DYNAMIC`   | `dynamic_rate`| `0`   | `1` → 200G / 100G selectable at runtime by the `rate_100g` pin (see the top-level README, "Runtime rate"). Needs `AXIL=1`. |

## Calling from your own project

To invoke the BD procs directly instead of going through this example, source
[dcmac.tcl](../tcl/dcmac.tcl) and call one of:

```tcl
bd_dcmac      $parentCell {dcmac_index 0} {dual_dcmac 0} {dcmac_axil 0} {board v80} {nclk_f ""} {dynamic_rate 0}
bd_dcmac_qsfp $parentCell {dcmac_index 0} {dual_dcmac 0} {dcmac_axil 0} {board v80} {nclk_f ""} {dynamic_rate 0}
```

`bd_dcmac` builds a flat block design with external ports. `bd_dcmac_qsfp` wraps the
same logic in a `qsfp_${2i}_n_${2i+1}` hierarchy with interface pins instead.

`parentCell` controls where the build lands — empty string puts it at the BD
root. The remaining params match the table above.

Both procs detect whether a BD is already open:

- **Standalone** — no BD open: the proc creates the BD, builds it, saves it,
  and exposes external ports at the top level.
- **Inline** — BD already open: the proc builds inside the caller's
  `parentCell` and exposes interface pins. The caller owns the BD lifecycle.
