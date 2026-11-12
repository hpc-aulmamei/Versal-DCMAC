# Versal DCMAC at 200 Gb/s

Reusable Vivado block design for the AMD DCMAC on Versal. Ships the HDL,
the TCL build script, and a standalone BD project so you can pull DCMAC into
a Versal design without rebuilding it from scratch.

DISCLAIMER: While tested and functional, this repository is still a work in progress and may need minor changes to fit other projects.

## Scope

Targets the V80 in 200GAUI-4 mode with RS(544) FEC. A single DCMAC instance
drives one QSFP56 cage; the package supports two instances on the same device
(`DCMAC_X1Y1` and `DCMAC_X0Y2`) and an optional dual-QSFP56 mode that uses
both GT quads of one DCMAC.

Both single-DCMAC and dual-QSFP have been tested on the Alveo V80.

## Repository organization

| Path | Purpose |
|---|---|
| `tcl/dcmac.tcl` | Main block design script. Exports `bd_dcmac` and `bd_dcmac_qsfp`. |
| `tcl/board_config.tcl` | Per-board DCMAC site dict, keyed on `(board, dcmac_index)`. |
| `hdl/` | Reset FSM, segment converters, control-port helpers, clock fan-outs. See `hdl/README.md`. |
| `example/` | Standalone BD project: `Makefile` + `create_dcmac_example.tcl`. |

## Requirements

- Vivado **2025.1** or newer

## Integrate in your design

`tcl/dcmac.tcl` exports two TCL procs (`bd_dcmac` and `bd_dcmac_qsfp`) that
build the DCMAC hierarchy in a Vivado block design. See
[example/](./example/) for parameters, usage, and how to call them from
your own project.

## External projects

Used by:

- [Coyote](https://github.com/fpgasystems/Coyote) — ETH Zurich's FPGA shell
  for cloud/data-center workloads.
- [SLASH](https://github.com/Xilinx/SLASH) — AMD's Versal accelerator
  framework.

## Hardware notes

- GT reference clock: 322.265625 MHz.
- DCMAC core clock: 782 MHz; AXIS clock: 391 MHz nominal (`nclk_f`).
- 200GAUI-4, RS(544) FEC.
- Each DCMAC site supports an optional second QSFP56 via the second GT quad.

## Runtime rate: 200G / 100G

With `dynamic_rate = 1` (last argument of `bd_dcmac` / `bd_dcmac_qsfp`, `DYNAMIC=1`
in the example; needs `dcmac_axil = 1`) a DCMAC switches between 200GAUI-4
(53.125G PAM4 lanes, RS(544) FEC) and 100CAUI-4 (25.78125G NRZ lanes, e.g.
100GBASE-SR4 / CR4) at runtime, without reprogramming the FPGA. The build then has:

- the DCMAC in *Dynamic Configuration*: configuration 0 is 200GAUI-4, configuration 1 is
  100CAUI-4 on the same port(s);
- a second GT line rate (LR1, 25.78125G NRZ) on each quad;
- TX converters with a half mode: at 100G a port takes two segments a cycle, so each
  512-bit AXIS beat goes out in two cycles (`hdl/axis_to_dcmac_seg.sv`);
- RX converters with segments 2-3 masked at 100G: the DCMAC leaves their ena / sop / eop
  at the last 200G values, which would otherwise splice stale data into every 100G frame
  (`hdl/dcmac_rx_seg_mask.v`);
- one input pin, `rate_100g` (any clock), that selects all of the above
  (`hdl/dcmac_rate_sel.v`).

One rate per DCMAC: the IP maps the GT lanes only for configurations that are all PAM4 or
all NRZ, so with `dual_dcmac` both cages switch together. The AXIS clock stays the same;
at 100G the TX side accepts a beat every other cycle and the RX side delivers half as
many beats.

### Port registers

Port *n* of the DCMAC (0, or 0 and 2 with `dual_dcmac`) has its registers at
`0x1000 * (n + 1)` on `s_axi`, the global block at `0x0000` (PG369 register map).

| Rate | FEC | `TX_MODE` (0x040) | `RX_MODE` (0x044) |
|---|---|---|---|
| 200G | RS(544), clause 119 | `0x00080211` | `0x00081801` |
| 100G | RS(528), clause 91 | `0x00450010` | `0x00050800` |
| 100G | none | `0x00000010` | `0x00000800` |

Fields: `[3:0]` data rate (1: 200G, 0: 100G), `TX[4]` / `RX[11]` statistics tick by
register, `TX[9]` / `RX[12]` PMA lane mux (1 for PAM4), `[20:16]` FEC mode (`0b01000`
RS(544) 200G, `0b00101` RS(528), `0b00000` none), `TX[22]` `ctl_tx_fec_four_lane_pmd`.
Set `TX[22]` with RS(528) at 100G: without it a V80 links with itself (its RX accepts both
framings), but a standard 100GBASE-SR4 / CR4 partner (seen with a ConnectX-5) never
detects one. There is no RX counterpart.

### Switching

For each step, "the channels" are the port register blocks of the active port(s): a 200G
port spans two channels, so blocks 1-2 (port 0) and 3-4 (port 2).

1. Write 1 to `0x030` and `0x038` (RX / TX channel flush) of the channels; wait 1 ms.
2. Write 3 to `0x0F0` and `0x0F8` (RX / TX reset) of the channels.
3. Set or clear `rate_100g`. The GT quads change line rate and reset themselves; wait
   for their reset done (about 0.25 s; 0.5 s is enough).
4. Write `0xFFFFFFFF` to `0x0F0` and `0x0F8` of the global block and all six channels.
5. Going to 100G: first write the 100G `TX_MODE` / `RX_MODE` to all six channels. Then,
   either way, write the target `TX_MODE` / `RX_MODE` to the active port(s).
6. Write 0 to `0x0F0` and `0x0F8` of the global block and all six channels; wait 1 ms;
   write 0 to the flush registers of step 1.

The link then comes up as after configuration (rx PHY status `0xC00` of the port). If it
does not within a few seconds, a GT RX datapath reset, or a rerun of the reset sequencer
(pulse `aresetn`), brings it up.

### Tested

On an Alveo V80 with `dual_dcmac = 1`, both DCMACs (all four cages): 200G and 100G in GT
near-end loopback at 60-8996 B frames and after repeated 200G / 100G switches; 200G and
100G cage to cage over copper (198.16 / 99.56 Gb/s, no errors); 100G RS(528) against a
Mellanox ConnectX-5 over 100GBASE-SR4 optics in both directions at line rate, frame and
byte counts matching on both sides. `dual_dcmac = 0` with `dynamic_rate = 1` is only checked to build
the block design.

## GT control for DCMAC Operation

### Resets

Reset process is controlled by the HDL module [dcmac_reset_ctrl_wrapper.v](hdl/dcmac_reset_ctrl_wrapper.v).

### Set swing and pre/post-emphasis

To be able to transmit, we need to set the corresponding `CH*_TXMAINCURSOR`, `CH*_TXPRECURSOR` and `CH*_TXPOSTCURSOR`. In general these parameters will depend on the board path from the transceiver pins to the QSFP cases.

* TXMAINCURSOR: Sets the voltage swing. For the v80 ports brought up so far, the value **52** was found to give good BER.
* TXPRECURSOR: Sets pre-emphasis. For the v80 ports brought up so far, the value **6** was found to give good BER.
* TXPOSTCURSOR: Sets post emphasis. For the v80 ports brought up so far, the value **6** was found to give good BER.

Notes:
* Take into account that for many DCMAC settings PAM4 is used, not NRZ binary signaling. Therefore, pre/post-emphasis needs to be set more carefully, as information is not only encoded in the polarity, but also the signal amplitude.
* We are dealing with analog circuits, actual driver output voltages will vary from chip to chip due to manufacture variability.
* There are 2 additional pre-emphasis drivers, for times -2 and-3, but these were not needed to get an stable link.  

For more info on Pre/post-emphasis, see section Pre-Emphasis of [this book](https://www.xilinx.com/publications/archives/books/serialio.pdf). 
[Docs](https://docs.amd.com/r/en-US/am017-versal-gtm-transceivers/TX-Configurable-Driver)

## DCMAC Documentation
* Clocks: Check [Clocking section](https://docs.amd.com/r/en-US/pg369-dcmac/Clocking)
  * To know the clocks configurations required for a specific DCMAC channel setting check [Clocking Relationships section](https://docs.amd.com/r/en-US/pg369-dcmac/Clocking-Relationships)
* Resets:
  * [Resets description](https://docs.amd.com/r/en-US/pg369-dcmac/Resets)
* Operational Guidelines
  * [Transmit Fixed Ethernet Startup Procedure without reconfiguration](https://docs.amd.com/r/en-US/pg369-dcmac/Transmit-Fixed-Ethernet-Startup-Procedure-when-Using-tx_core_reset)
  * [Receive Fixed Ethernet Startup Procedure without reconfiguration](https://docs.amd.com/r/en-US/pg369-dcmac/Receive-Fixed-Ethernet-Startup-Procedure-when-Using-rx_core_reset)
* [Statistics Monitoring] (https://docs.amd.com/r/en-US/pg369-dcmac/Statistics-Monitoring)
* Register Map: [Download excel with register map spec](https://docs.amd.com/viewer/book-attachment/79NY3iPGqwGWicjQjhDCRQ/V~R8bj2ZvfFnn4Kg7Syoiw-79NY3iPGqwGWicjQjhDCRQ)

## Debug

### GT Loopbacks

Consider using the GTM provided loopbacks to decouple problems. See docs [here](https://docs.amd.com/r/en-US/am017-versal-gtm-transceivers/Ports-and-Attributes?tocId=VCPR5g15KRqYyFFYnjyWoQ)

### IBERT

Allows detecting signal quality issues. Here we can see a snapshot of a working link using PAM4 modulation:
![image](./images/ibert.png)
* ES Sample shows analog values at their sample point (we do not see the actual eye diagram)
* We can also see a histogram of the ES samples (it can be reset with the circular arrow in the top left corner)
* SNR: We observed that ~24 SNR provides good link stability.

Accessing these plots from the hardware manager should allow you to detect problems in the physical layer.

## License

MIT Licence

- Copyright (c) 2026, Systems Group, ETH Zurich
- Copyright (C) 2025 Advanced Micro Devices

## Acknowledgments  

This work was supported in part by AMD under the [Heterogeneous Accelerated Compute Clusters (HACC) program](https://www.amd-haccs.io/).
