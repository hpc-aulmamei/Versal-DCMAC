/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

`timescale 1ns / 1ps

module axis_to_dcmac_seg (
    // Clock, reset
    input  logic         aclk,
    input  logic         aresetn,

    // 100G port (2 segments a cycle): each 512-bit beat goes out as two
    // 256-bit halves on segments 0 and 1. aclk domain, change only while idle.
    input  logic         half,

    // AXI Stream input
    input  logic [511:0] s_axis_tdata,
    input  logic [63:0]  s_axis_tkeep,
    input  logic         s_axis_tlast,
    input  logic         s_axis_tvalid,
    output logic         s_axis_tready,

    // Segmented AXI stream outputs
    output logic [127:0] tx_data_0,
    output logic         tx_ena_0,
    output logic         tx_sop_0,
    output logic         tx_eop_0,
    output logic [3:0]   tx_mty_0,
    output logic         tx_err_0,

    output logic [127:0] tx_data_1,
    output logic         tx_ena_1,
    output logic         tx_sop_1,
    output logic         tx_eop_1,
    output logic [3:0]   tx_mty_1,
    output logic         tx_err_1,

    output logic [127:0] tx_data_2,
    output logic         tx_ena_2,
    output logic         tx_sop_2,
    output logic         tx_eop_2,
    output logic [3:0]   tx_mty_2,
    output logic         tx_err_2,

    output logic [127:0] tx_data_3,
    output logic         tx_ena_3,
    output logic         tx_sop_3,
    output logic         tx_eop_3,
    output logic [3:0]   tx_mty_3,
    output logic         tx_err_3,

    // Flow control
    output logic         tx_valid,
    input  logic         tx_ready
);

    // Keep track of first beat of a packet to correctly assert SOP
    logic is_next_beat_first;

    always_ff @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            is_next_beat_first <= 1'b1;
        end else if (s_axis_tvalid && s_axis_tready) begin
            if (s_axis_tlast) begin
                is_next_beat_first <= 1'b1;
            end else begin
                is_next_beat_first <= 1'b0;
            end
        end
    end

    // Helper function to convert 16-bit TKEEP to 4-bit MTY (number of empty bytes)
    function automatic logic [3:0] get_mty(input logic [15:0] keep);
        case (keep)
            16'hFFFF: return 4'd0;
            16'h7FFF: return 4'd1;
            16'h3FFF: return 4'd2;
            16'h1FFF: return 4'd3;
            16'h0FFF: return 4'd4;
            16'h07FF: return 4'd5;
            16'h03FF: return 4'd6;
            16'h01FF: return 4'd7;
            16'h00FF: return 4'd8;
            16'h007F: return 4'd9;
            16'h003F: return 4'd10;
            16'h001F: return 4'd11;
            16'h000F: return 4'd12;
            16'h0007: return 4'd13;
            16'h0003: return 4'd14;
            16'h0001: return 4'd15;
            default:  return 4'd0;
        endcase
    endfunction

    // Half mode: phase 0 sends bytes 0..31 of the beat, phase 1 bytes 32..63.
    // A last beat with nothing in the upper half ends in phase 0.
    logic phase;
    logic beat_done;
    assign beat_done = !half || phase || (s_axis_tlast && !s_axis_tkeep[32]);

    always_ff @(posedge aclk) begin
        if (aresetn == 1'b0 || !half) begin
            phase <= 1'b0;
        end else if (s_axis_tvalid && tx_ready) begin
            phase <= !beat_done;
        end
    end

    // Flow control
    assign tx_valid      = s_axis_tvalid;
    assign s_axis_tready = tx_ready && beat_done;

    // Data routing
    logic [511:0] seg_data;
    logic [63:0]  seg_keep;
    logic         seg_last;     // this cycle carries the end of the packet
    always_comb begin
        if (half) begin
            seg_data = {256'd0, phase ? s_axis_tdata[511:256] : s_axis_tdata[255:0]};
            seg_keep = {32'd0, phase ? s_axis_tkeep[63:32] : s_axis_tkeep[31:0]};
            seg_last = s_axis_tlast && beat_done;
        end else begin
            seg_data = s_axis_tdata;
            seg_keep = s_axis_tkeep;
            seg_last = s_axis_tlast;
        end
    end

    assign tx_data_0 = seg_data[127:0];
    assign tx_data_1 = seg_data[255:128];
    assign tx_data_2 = seg_data[383:256];
    assign tx_data_3 = seg_data[511:384];

    // Tie off error
    assign tx_err_0 = 1'b0;
    assign tx_err_1 = 1'b0;
    assign tx_err_2 = 1'b0;
    assign tx_err_3 = 1'b0;

    always_comb begin
        // Default values to prevent latches
        tx_ena_0 = 1'b0; tx_sop_0 = 1'b0; tx_eop_0 = 1'b0; tx_mty_0 = 4'd0;
        tx_ena_1 = 1'b0; tx_sop_1 = 1'b0; tx_eop_1 = 1'b0; tx_mty_1 = 4'd0;
        tx_ena_2 = 1'b0; tx_sop_2 = 1'b0; tx_eop_2 = 1'b0; tx_mty_2 = 4'd0;
        tx_ena_3 = 1'b0; tx_sop_3 = 1'b0; tx_eop_3 = 1'b0; tx_mty_3 = 4'd0;

        if (s_axis_tvalid) begin
            // Determine enabled segments
            if (seg_last == 1'b0) begin
                // Not the last beat; all segments enabled (two in half mode)
                tx_ena_0 = 1'b1;
                tx_ena_1 = 1'b1;
                tx_ena_2 = !half;
                tx_ena_3 = !half;
            end else begin
                // Last beat; enabled of a segment based on whether the LSB of that segment's keep is 1
                tx_ena_0 = seg_keep[0];
                tx_ena_1 = seg_keep[16];
                tx_ena_2 = seg_keep[32];
                tx_ena_3 = seg_keep[48];
            end

            // Start of Packet (SOP)
            if (is_next_beat_first && !phase) begin
                tx_sop_0 = 1'b1;
            end

            // 3. End of Packet (EOP); based on the highest enabled segment during the last beat
            if (seg_last) begin
                if      (tx_ena_3) tx_eop_3 = 1'b1;
                else if (tx_ena_2) tx_eop_2 = 1'b1;
                else if (tx_ena_1) tx_eop_1 = 1'b1;
                else if (tx_ena_0) tx_eop_0 = 1'b1;
            end

            // mty calculation, based on the tkeep, and only relavant for the last beat
            if (seg_last) begin
                if (tx_eop_0) tx_mty_0 = get_mty(seg_keep[15:0]);
                if (tx_eop_1) tx_mty_1 = get_mty(seg_keep[31:16]);
                if (tx_eop_2) tx_mty_2 = get_mty(seg_keep[47:32]);
                if (tx_eop_3) tx_mty_3 = get_mty(seg_keep[63:48]);
            end
        end
    end

endmodule