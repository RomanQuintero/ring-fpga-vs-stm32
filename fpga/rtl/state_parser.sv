`timescale 1ns/1ps
module state_parser(input logic clk,rst,enable,valid,error,input logic [7:0] data,
 output logic frame_valid,output logic side_left,
 output logic signed [31:0] values [0:8],
 output logic [7:0] tick_text [0:18], output logic [4:0] tick_length);
 // Header is literal STATE,1,. Fields 2=tick, 3=side, 4..12=integers.
 logic [3:0] prefix,field;
 logic bad,negative,digits,side_seen,cr_seen;
 logic [31:0] number;
 logic [63:0] tick_number;
 logic [4:0] tick_count;
 logic [7:0] line_length;
 function automatic [7:0] header(input logic [3:0] i);
  case(i) 0:header="S";1:header="T";2:header="A";3:header="T";
   4:header="E";5:header=",";6:header="1";default:header=",";endcase
 endfunction
 task automatic clear_line;
  begin prefix<=0; field<=2; bad<=0; negative<=0; digits<=0; side_seen<=0;
   cr_seen<=0; number<=0; tick_number<=0; tick_count<=0; line_length<=0; end
 endtask
 always_ff @(posedge clk) begin
  if(rst) begin clear_line(); frame_valid<=0; side_left<=0; tick_length<=0;
   for(int i=0;i<9;i++) values[i]<=0;
   for(int i=0;i<19;i++) tick_text[i]<=0;
  end else begin
   frame_valid<=0;
   if(error) bad<=1;
   if(valid) begin
    if(data==10) begin
     if(enable && !bad && prefix==8 && field==12 && digits &&
        values[6]>0 && values[7]>0 && !negative && number>0 && number<=$unsigned(values[7])) begin
      values[8]<=number;
      tick_length<=tick_count;
      frame_valid<=1;
     end
     clear_line();
    end else if(!enable || bad) bad<=1;
    else if(line_length==192 || cr_seen) bad<=1;
    else begin
     line_length<=line_length+1;
     if(data==13) begin
      if(field!=12 || !digits || prefix!=8) bad<=1;
      cr_seen<=1;
     end else if(prefix<8) begin
      if(data!=header(prefix)) bad<=1; else prefix<=prefix+1;
     end else if(field==2) begin
      if(data==",") begin
       if(!digits) bad<=1;
       else begin
        if(tick_count==0) begin tick_text[0]<="0"; tick_count<=1; end
        field<=3; digits<=0;
       end
      end else if(data>="0" && data<="9") begin
       digits<=1;
       if(tick_number>64'd922337203685477580 ||
          (tick_number==64'd922337203685477580 && data>"7")) bad<=1;
       else begin
        tick_number<=tick_number*10+(data-8'd48);
        if(tick_count!=0 || data!="0") begin
         if(tick_count==19) bad<=1;
         else begin tick_text[tick_count]<=data; tick_count<=tick_count+1; end
        end
       end
      end else bad<=1;
     end else if(field==3) begin
      if(!side_seen && (data=="L" || data=="R")) begin side_left<=data=="L"; side_seen<=1; end
      else if(side_seen && data==",") begin field<=4; number<=0; digits<=0; negative<=0; end
      else bad<=1;
     end else begin
      if(data==",") begin
       if(!digits || field==12) bad<=1;
       else begin
        values[field-4]<=negative ? -$signed(number) : $signed(number);
        field<=field+1; number<=0; digits<=0; negative<=0;
       end
      end else if(data=="-" && !digits && !negative) negative<=1;
      else if(data>="0" && data<="9") begin
       digits<=1;
       if(number>32'd214748364 || (number==32'd214748364 &&
          (data-8'd48)>(negative ? 8 : 7))) bad<=1;
       else number<=number*10+(data-8'd48);
      end else bad<=1;
     end
    end
   end
  end
 end
endmodule
