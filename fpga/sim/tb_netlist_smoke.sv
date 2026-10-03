`timescale 1ns/1ps
module tb_netlist_smoke;
 logic CLK100MHZ=0,uart_rx_in=1;
 wire uart_tx_out;
 wire [3:0] led;
 ring_fpga_top dut(.*);
 always #5 CLK100MHZ=~CLK100MHZ;
 string line="";
 logic [7:0] b;
 localparam integer BIT_NS=8680;
 initial begin
  #700000;
  begin
   string request="\nSTATE,1,42,R,480,240,0,0,240,240,960,480,80\n";
   for(int k=0;k<request.len();k++) begin
    uart_rx_in=0; #BIT_NS;
    for(int i=0;i<8;i++) begin uart_rx_in=request[k][i]; #BIT_NS; end
    uart_rx_in=1; #BIT_NS;
   end
  end
 end
 initial forever begin
  @(negedge uart_tx_out); #(BIT_NS/2);
  if(uart_tx_out!==0) $fatal(1,"Start bit");
  for(int i=0;i<8;i++) begin #BIT_NS; b[i]=uart_tx_out; end
  #BIT_NS;
  if(uart_tx_out!==1) $fatal(1,"Stop bit");
  if(b==10) begin
   if(line!="ACT,1,42,DOWN") $fatal(1,"Netlist reply mismatch: %s",line);
   $display("PASS NETLIST: %s",line); $finish;
  end else line={line,string'(b)};
 end
 initial begin #10000000; $fatal(1,"Netlist UART timeout led=%b",led); end
endmodule
