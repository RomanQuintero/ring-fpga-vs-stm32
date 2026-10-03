`timescale 1ns/1ps
module uart_rx #(parameter integer CLOCK_HZ=100000000, BAUD=115200)(
 input logic clk,rst,rx, output logic [7:0] data, output logic valid,error);
 localparam integer DIV=(CLOCK_HZ+BAUD/2)/BAUD;
 (* ASYNC_REG="TRUE" *) logic meta=1, sync_rx=1;
 always_ff @(posedge clk) begin meta<=rx; sync_rx<=meta; end
 typedef enum logic [2:0] {IDLE,START,BITS,STOP,RECOVER} st_t;
 st_t state;
 logic [$clog2(DIV+1)-1:0] timer;
 logic [2:0] bit_index;
 logic [7:0] shift;
 always_ff @(posedge clk) begin
  if(rst) begin state<=IDLE; timer<=0; valid<=0; error<=0; data<=0; bit_index<=0; shift<=0; end
  else begin
   valid<=0; error<=0;
   case(state)
    IDLE: if(!sync_rx) begin timer<=DIV/2-1; state<=START; end
    START: if(timer!=0) timer<=timer-1; else if(sync_rx) state<=IDLE;
           else begin timer<=DIV-1; bit_index<=0; state<=BITS; end
    BITS: if(timer!=0) timer<=timer-1; else begin
     shift[bit_index]<=sync_rx; timer<=DIV-1;
     if(bit_index==7) state<=STOP; else bit_index<=bit_index+1;
    end
    STOP: if(timer!=0) timer<=timer-1; else begin
     if(sync_rx) begin data<=shift; valid<=1; state<=IDLE; end
     else begin error<=1; state<=RECOVER; end
    end
    RECOVER: if(sync_rx) state<=IDLE;
    default: state<=IDLE;
   endcase
  end
 end
endmodule
