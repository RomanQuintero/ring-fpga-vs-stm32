`timescale 1ns/1ps
module ring_fpga_top #(parameter integer CLOCK_HZ=100000000, BAUD=115200)(
 input logic CLK100MHZ,uart_rx_in,output logic uart_tx_out,
 output logic [3:0] led);
 logic [15:0] powerup=0;
 wire rst= !(&powerup);
 always_ff @(posedge CLK100MHZ) if(!(&powerup)) powerup<=powerup+1;
 wire clk=CLK100MHZ;
 logic [7:0] rx_data,tx_data;
 logic rx_valid,rx_error,tx_start,tx_busy,tx_done;
 uart_rx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) rx(.clk,.rst,.rx(uart_rx_in),.data(rx_data),.valid(rx_valid),.error(rx_error));
 uart_tx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) tx(.clk,.rst,.start(tx_start),.data(tx_data),.tx(uart_tx_out),.busy(tx_busy),.done(tx_done));
 typedef enum logic [3:0] {WAIT_FRAME,Q_PREP,Q_START,Q_WAIT,NN_START,NN_ACCEPT,NN_WAIT,SEND_BYTE,WAIT_TX} st_t;
 st_t state;
 logic frame_valid,left_side;
 logic signed [31:0] values [0:8],saved [0:8];
 logic [7:0] tick_text [0:18],reply_tick [0:18];
 logic [4:0] tick_length,reply_length;
 logic saved_left;
 state_parser parser(.clk,.rst,.enable(state==WAIT_FRAME),.valid(rx_valid),.error(rx_error),
  .data(rx_data),.frame_valid,.side_left(left_side),.values,.tick_text,.tick_length);
 logic [2:0] input_index;
 logic signed [32:0] quant_value,adapted_value;
 logic [31:0] quant_denominator,adapted_denominator;
 logic quant_start,quant_done;
 logic signed [7:0] quant_result,nn_x [0:4];
 logic nn_start,nn_busy,nn_done;
 logic [1:0] nn_action,reply_action;
 input_quantizer quant(.clk,.rst,.start(quant_start),.value(quant_value),
  .denominator(quant_denominator),.result(quant_result),.done(quant_done));
 // Related 50 MHz clock keeps the verified NN unchanged and closes its MAC path.
 // Inputs remain stable throughout inference; start is held until busy acknowledges.
 logic nn_clock=0;
 always_ff @(posedge clk) nn_clock<=~nn_clock;
 pong_nn nn(.clk(nn_clock),.rst,.start(nn_start),.x(nn_x),.busy(nn_busy),.done(nn_done),.action(nn_action));
 always_comb begin
  adapted_value=0; adapted_denominator=1;
  case(input_index)
   0: begin
    adapted_value=saved_left ? $signed({1'b0,saved[6]})-$signed({saved[0][31],saved[0]}) : $signed({saved[0][31],saved[0]});
    adapted_denominator=saved[6];
   end
   1: begin adapted_value=$signed({saved[1][31],saved[1]}); adapted_denominator=saved[7]; end
   2: begin
    adapted_value=saved_left ? -$signed({saved[2][31],saved[2]}) : $signed({saved[2][31],saved[2]});
    adapted_denominator=540;
   end
   3: begin adapted_value=$signed({saved[3][31],saved[3]}); adapted_denominator=540; end
   4: begin adapted_value=$signed({saved[4][31],saved[4]}); adapted_denominator=saved[7]; end
   default: begin adapted_value=0; adapted_denominator=1; end
  endcase
 end
 logic [5:0] char_index;
 logic [2:0] action_length;
 logic [5:0] last_char;
 integer action_index;
 always_comb begin
  action_length=reply_action==0 ? 2 : 4;
  last_char=7+reply_length+action_length;
  action_index=char_index-7-reply_length;
  tx_data=10;
  if(char_index<6) begin
   case(char_index) 0:tx_data="A";1:tx_data="C";2:tx_data="T";
    3:tx_data=",";4:tx_data="1";5:tx_data=",";default:tx_data=10;endcase
  end else if(char_index<6+reply_length) tx_data=reply_tick[char_index-6];
  else if(char_index==6+reply_length) tx_data=",";
  else if(char_index<last_char) begin
   if(reply_action==0) tx_data=action_index==0 ? "U" : "P";
   else if(reply_action==1) begin
    case(action_index) 0:tx_data="S";1:tx_data="T";2:tx_data="A";default:tx_data="Y";endcase
   end else begin
    case(action_index) 0:tx_data="D";1:tx_data="O";2:tx_data="W";default:tx_data="N";endcase
   end
  end
 end
 always_ff @(posedge clk) begin
  if(rst) begin
   state<=WAIT_FRAME; quant_start<=0; nn_start<=0; tx_start<=0; input_index<=0;
   reply_length<=0; reply_action<=1; saved_left<=0; char_index<=0; led<=0; quant_value<=0; quant_denominator<=1;
   for(int i=0;i<9;i++) saved[i]<=0;
   for(int i=0;i<19;i++) reply_tick[i]<=0;
   for(int i=0;i<5;i++) nn_x[i]<=0;
  end else begin
   quant_start<=0; nn_start<=0; tx_start<=0;
   if(rx_valid) led[0]<=~led[0];
   case(state)
    WAIT_FRAME: if(frame_valid) begin
     for(int i=0;i<9;i++) saved[i]<=values[i];
     for(int i=0;i<19;i++) reply_tick[i]<=tick_text[i];
     saved_left<=left_side; reply_length<=tick_length; input_index<=0;
     led[1]<=~led[1]; state<=Q_PREP;
    end
    Q_PREP: begin quant_value<=adapted_value; quant_denominator<=adapted_denominator; state<=Q_START; end
    Q_START: begin quant_start<=1; state<=Q_WAIT; end
    Q_WAIT: if(quant_done) begin
     nn_x[input_index]<=quant_result;
     if(input_index==4) state<=NN_START;
     else begin input_index<=input_index+1; state<=Q_PREP; end
    end
    NN_START: begin nn_start<=1; state<=NN_ACCEPT; end
    NN_ACCEPT: begin
     if(nn_busy) begin nn_start<=0; state<=NN_WAIT; end
     else nn_start<=1;
    end
    NN_WAIT: if(nn_done) begin reply_action<=nn_action; char_index<=0; led[2]<=~led[2]; state<=SEND_BYTE; end
    SEND_BYTE: if(!tx_busy) begin tx_start<=1; state<=WAIT_TX; end
    WAIT_TX: if(tx_done) begin
     if(char_index==last_char) begin led[3]<=~led[3]; state<=WAIT_FRAME; end
     else begin char_index<=char_index+1; state<=SEND_BYTE; end
    end
    default: state<=WAIT_FRAME;
   endcase
  end
 end
endmodule
