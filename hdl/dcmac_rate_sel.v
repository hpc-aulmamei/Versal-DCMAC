// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps

// Rate select of a DCMAC built with dynamic_rate (tcl/dcmac.tcl): one bit to
// everything that changes between 200G and 100G.
//   rate_100g = 0: DCMAC configuration 0 (200GAUI-4), GT line rate 0 (53.125G PAM4),
//                  converters at four segments a cycle
//   rate_100g = 1: DCMAC configuration 1 (100CAUI-4), GT line rate 1 (25.78125G NRZ),
//                  converters at two segments a cycle
// rate_100g may come from any clock. Changing it changes the GT line rate, which
// resets the GT quads; the DCMAC port registers must follow (see README.md,
// "Runtime rate").
module dcmac_rate_sel (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 sys_clk CLK" *)
    input  wire       sys_clk,
    input  wire       rate_100g,
    output reg  [2:0] config_switch = 3'd0,     // DCMAC config_switch
    output reg  [7:0] gt_rate = 8'd0,           // gtwiz ch_txrate / ch_rxrate
    output reg        half = 1'b0               // converters: two segments a cycle
);
    wire rate_s;
    xpm_cdc_single #(.DEST_SYNC_FF(4), .INIT_SYNC_FF(0), .SIM_ASSERT_CHK(0), .SRC_INPUT_REG(0)) inst_rate_cdc (
        .src_clk(1'b0), .src_in(rate_100g), .dest_clk(sys_clk), .dest_out(rate_s));

    always @(posedge sys_clk) begin
        config_switch <= {2'd0, rate_s};
        gt_rate       <= {7'd0, rate_s};
        half          <= rate_s;
    end
endmodule
