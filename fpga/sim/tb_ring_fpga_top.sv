`timescale 1ns/1ps
module tb_ring_fpga_top;
 logic CLK100MHZ=0,uart_rx_in=1;
 wire uart_tx_out;
 wire [3:0] led;
 ring_fpga_top dut(.*);
 always #5 CLK100MHZ=~CLK100MHZ;
 localparam integer BIT_NS=8680;
 string received_line="",last_line="";
 integer responses=0,passed=0;
 logic [7:0] byte_rx;
 // Independent UART sink samples the physical TX wire, not DUT internals.
 initial forever begin
  @(negedge uart_tx_out);
  #(BIT_NS/2);
  if(uart_tx_out!==0) $fatal(1,"TX start bit");
  for(int i=0;i<8;i++) begin #(BIT_NS); byte_rx[i]=uart_tx_out; end
  #(BIT_NS);
  if(uart_tx_out!==1) $fatal(1,"TX stop bit");
  if(byte_rx==10) begin
   last_line={received_line,"\n"}; received_line=""; responses++;
  end else received_line={received_line,string'(byte_rx)};
 end
 task automatic send_byte(input byte b,input integer period_ns=BIT_NS);
  uart_rx_in=0; #(period_ns);
  for(int i=0;i<8;i++) begin uart_rx_in=b[i]; #(period_ns); end
  uart_rx_in=1; #(period_ns);
 endtask
 task automatic send_line(input string s,input integer period_ns=BIT_NS);
  for(int i=0;i<s.len();i++) send_byte(s[i],period_ns);
 endtask
 task automatic expect_reply(input string expected,input integer before_count);
  fork : deadline
   begin wait(responses>before_count); end
   begin #5000000; $fatal(1,"ACT timeout: %s",expected); end
  join_any
  disable deadline;
  if(responses!=before_count+1 || last_line!=expected)
   $fatal(1,"ACT mismatch: got %s expected %s",last_line,expected);
  // Whole exchange deadline (send starts in caller) checked separately.
  #100000;
 endtask
 task automatic rejected(input string s);
  integer before_count;
  before_count=responses; send_line(s); #3500000;
  if(responses!=before_count) $fatal(1,"Malformed STATE produced ACT: %s",s);
 endtask
 integer fd,n,status,before_count,q [0:4],period_ns;
 string request,expected;
 time started;
 initial begin
  #700000;
  fd=$fopen("uart_vectors.txt","r"); if(!fd) $fatal;
  while(!$feof(fd)) begin
   n=$fgets(request,fd);
   if(n!=0) begin
    n=$fgets(expected,fd); if(!n) $fatal;
    status=$fscanf(fd,"%d %d %d %d %d\n",q[0],q[1],q[2],q[3],q[4]); if(status!=5) $fatal;
    before_count=responses;
    // Nominal and +/- 2% baud mismatch exercise center sampling.
    period_ns=passed%3==0 ? 8510 : passed%3==1 ? 8850 : BIT_NS;
    started=$time; send_line(request,period_ns); expect_reply(expected,before_count);
    if($time-started>16666666) $fatal(1,"Host deadline exceeded");
`ifndef POST_NETLIST
    for(int i=0;i<5;i++) if(dut.nn_x[i]!==q[i]) $fatal(1,"Input normalization mismatch case %0d input %0d got %0d expected %0d",passed,i,dut.nn_x[i],q[i]);
`endif
    passed++;
    if(passed==1) begin
     rejected("\n");
     rejected("STATE,2,1,R,1,1,1,1,1,1,960,480,80\n");
     rejected("STATE,1,9223372036854775808,R,1,1,1,1,1,1,960,480,80\n");
     rejected("STATE,1,1,Q,1,1,1,1,1,1,960,480,80\n");
     rejected("STATE,1,1,R,2147483648,1,1,1,1,1,960,480,80\n");
     rejected("STATE,1,1,R,1,1,1,1,1,1,0,480,80\n");
     rejected("STATE,1,1,R,1,1,1,1,1,1,960,480,481\n");
     rejected("STATE,1,1,R,1,1,1,1,1,1,960,480,80,1\n");
     rejected("STATE,1,1,R,1,1,1,1,1,1,960,480,\n");
     rejected({{200{"X"}},"\n"});
     rejected("partial\n");
     // UART framing error / break, then LF restores parser boundary.
     uart_rx_in=0; #(BIT_NS*12); uart_rx_in=1; #(BIT_NS*2); rejected("\n");
     before_count=responses;
     send_line(request); // second complete frame begins while reply is being sent
     send_line(request);
     #3500000;
     if(responses!=before_count+1 || last_line!=expected) $fatal(1,"Busy frame handling failed");
     // CRLF and leading-zero tick: canonical echo remains host-equivalent.
     before_count=responses;
     send_line("STATE,1,0000,R,480,240,0,0,240,240,960,480,80");
     send_byte(8'h0d); send_byte(8'h0a);
     expect_reply("ACT,1,0,DOWN\n",before_count);
    end
   end
  end
  $fclose(fd);
  if(passed!=38) $fatal(1,"Incorrect test count %0d",passed);
  $display("PASS UART: %0d reference STATEs, normalized inputs/actions, baud tolerance, malformed/break recovery, busy rejection, CRLF, tick64, deadline",passed);
  $finish;
 end
 initial begin #1000000000; $fatal(1,"Global timeout"); end
endmodule
