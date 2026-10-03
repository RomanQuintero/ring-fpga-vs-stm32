`timescale 1ns/1ps
// Temporary physical wiring diagnostic. No parser, UART sampling or NN.
module uart_loopback_top(input wire CLK100MHZ,uart_rx_in,
 output wire uart_tx_out,output wire [3:0] led);
 reg [25:0] heartbeat=0;
 always @(posedge CLK100MHZ) heartbeat<=heartbeat+1;
 assign uart_tx_out=uart_rx_in;
 assign led={1'b0,1'b1,heartbeat[25],uart_rx_in};
endmodule
