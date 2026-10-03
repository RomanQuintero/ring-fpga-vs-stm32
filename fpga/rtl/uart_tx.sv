`timescale 1ns/1ps
module uart_tx #(parameter integer CLOCK_HZ=100000000, BAUD=115200)(
 input logic clk,rst,start,input logic [7:0] data,
 output logic tx,busy,done);
 localparam integer DIV=(CLOCK_HZ+BAUD/2)/BAUD;
 logic [$clog2(DIV+1)-1:0] timer;
 logic [9:0] shift;
 logic [3:0] bit_index;
 always_ff @(posedge clk) begin
  if(rst) begin tx<=1; busy<=0; done<=0; timer<=0; bit_index<=0; shift<=10'h3ff; end
  else begin
   done<=0;
   if(!busy) begin
    if(start) begin shift<={1'b1,data,1'b0}; tx<=0; busy<=1; timer<=DIV-1; bit_index<=0; end
   end else if(timer!=0) timer<=timer-1;
   else if(bit_index==9) begin tx<=1; busy<=0; done<=1; end
   else begin shift<={1'b1,shift[9:1]}; tx<=shift[1]; bit_index<=bit_index+1; timer<=DIV-1; end
  end
 end
endmodule
