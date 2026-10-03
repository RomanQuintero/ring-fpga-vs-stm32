`timescale 1ns/1ps
module input_quantizer(input logic clk,rst,start,input logic signed [32:0] value,
 input logic [31:0] denominator,output logic signed [7:0] result,output logic done);
 // Exact rational scale 127, nearest-even rounding, clip [-127,127].
 logic active,negative,preparing;
 logic [32:0] saved_magnitude;
 logic [37:0] numerator;
 logic [32:0] remainder;
 logic [31:0] divisor;
 logic [7:0] quotient;
 logic [5:0] bit_index;
 logic [32:0] shifted,reduced;
 logic [7:0] next_q,rounded;
 logic [32:0] magnitude;
 always_comb begin
  magnitude=value<0 ? -value : value;
  shifted={remainder[31:0],numerator[bit_index]};
  reduced=shifted>={1'b0,divisor} ? shifted-{1'b0,divisor} : shifted;
  next_q={quotient[6:0],shifted>={1'b0,divisor}};
  rounded=next_q;
  if((reduced<<1)>{1'b0,divisor} ||
    ((reduced<<1)=={1'b0,divisor} && next_q[0])) rounded=next_q+1;
 end
 always_ff @(posedge clk) begin
  if(rst) begin active<=0; preparing<=0; saved_magnitude<=0; done<=0; result<=0; numerator<=0; remainder<=0;
   divisor<=1; quotient<=0; bit_index<=0; negative<=0; end
  else begin
   done<=0;
   if(start && !active && !preparing) begin
    if(denominator==0) begin result<=0; done<=1; end
    else if(magnitude>={1'b0,denominator}) begin result<=value<0 ? -8'sd127 : 8'sd127; done<=1; end
    else begin
     saved_magnitude<=magnitude; divisor<=denominator; negative<=value<0;
     remainder<=0; quotient<=0; bit_index<=37; preparing<=1;
    end
   end else if(preparing) begin
    numerator<=({5'd0,saved_magnitude}<<7)-{5'd0,saved_magnitude};
    preparing<=0; active<=1;
   end else if(active) begin
    remainder<=reduced; quotient<=next_q;
    if(bit_index==0) begin
     result<=negative ? -$signed(rounded) : $signed(rounded); done<=1; active<=0;
    end else bit_index<=bit_index-1;
   end
  end
 end
endmodule
