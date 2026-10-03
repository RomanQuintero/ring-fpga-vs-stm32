`timescale 1ns/1ps
module pong_nn (
    input logic clk, rst, start,
    input logic signed [7:0] x [0:4],
    output logic busy, done,
    output logic [1:0] action
);
    `include "pong_weights.svh"
    `include "pong_requant.svh"
    typedef enum logic [2:0] {IDLE,L1_INIT,L1_MAC,REQUANT,L2_INIT,L2_MAC,ARGMAX} state_t;
    state_t state;
    logic signed [7:0] inputs_q [0:4];
    logic signed [7:0] hidden_q [0:15];
    logic signed [31:0] logits [0:2];
    logic signed [31:0] acc;
    logic signed [15:0] product;
    logic signed [31:0] extended_product;
    integer neuron, index, output_index;
    logic [7:0] q;
    // Both operands signed; product is explicitly extended before accumulation.
    always_comb begin
        product = 16'sd0;
        if (state == L1_MAC) product = inputs_q[index] * W1[index][neuron];
        if (state == L2_MAC) product = hidden_q[index] * W2[index][output_index];
        extended_product = {{16{product[15]}},product};
    end
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE; busy <= 0; done <= 0; action <= 0;
            neuron <= 0; index <= 0; output_index <= 0; acc <= 0; q <= 0;
            for (int i=0;i<5;i++) inputs_q[i] <= 0;
            for (int i=0;i<16;i++) hidden_q[i] <= 0;
            for (int i=0;i<3;i++) logits[i] <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE: if (start) begin
                    for (int i=0;i<5;i++) inputs_q[i] <= x[i];
                    busy <= 1; neuron <= 0; state <= L1_INIT;
                end
                L1_INIT: begin acc <= B1[neuron]; index <= 0; state <= L1_MAC; end
                L1_MAC: begin
                    acc <= acc + extended_product;
                    if (index == 4) begin q <= 0; state <= REQUANT; end
                    else index <= index + 1;
                end
                // Negative accumulators naturally map to zero (ReLU).
                // Thresholds encode exact reference rounding, including ties.
                REQUANT: begin
                    if (q == 127) begin
                        hidden_q[neuron] <= 8'sd127;
                        if (neuron == 15) begin output_index <= 0; state <= L2_INIT; end
                        else begin neuron <= neuron + 1; state <= L1_INIT; end
                    end else if (acc >= HQ_THRESHOLD[q+1]) q <= q + 1;
                    else begin
                        hidden_q[neuron] <= $signed(q);
                        if (neuron == 15) begin output_index <= 0; state <= L2_INIT; end
                        else begin neuron <= neuron + 1; state <= L1_INIT; end
                    end
                end
                L2_INIT: begin acc <= B2[output_index]; index <= 0; state <= L2_MAC; end
                L2_MAC: begin
                    acc <= acc + extended_product;
                    if (index == 15) begin
                        logits[output_index] <= acc + extended_product;
                        if (output_index == 2) state <= ARGMAX;
                        else begin output_index <= output_index + 1; state <= L2_INIT; end
                    end else index <= index + 1;
                end
                // Strict comparisons preserve numpy's first-index tie rule.
                ARGMAX: begin
                    if (logits[1] > logits[0]) begin
                        if (logits[2] > logits[1]) action <= 2; else action <= 1;
                    end else begin
                        if (logits[2] > logits[0]) action <= 2; else action <= 0;
                    end
                    done <= 1; busy <= 0; state <= IDLE;
                end
                default: begin state <= IDLE; busy <= 0; end
            endcase
        end
    end
endmodule
