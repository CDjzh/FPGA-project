// M0/DMZ thumb-board matrix: rows active-low/open-drain, columns external 10k pullups.
// One row per millisecond, 20ms stable-sweep debounce; press-only, no repeat.
module tj_keypad #(parameter CLOCK_HZ=40000000)(input clk,rst,input[3:0] columns,
 output[3:0] rows,input tour_switch,output reg[15:0] events,output reg tour_on,tour_off,output[15:0] held,output ms_tick);
localparam STEP=CLOCK_HZ/1000;
reg[15:0] tick;reg[1:0] row;(* async_reg="true" *)reg[3:0] c1,c2;(* async_reg="true" *)reg[1:0] ss;
reg[15:0] sweep,candidate,stable;reg[2:0] debounce;
reg switch_candidate,switch_stable;reg[2:0] switch_debounce;
assign held=(stable==16'hffff)?16'd0:stable;
assign ms_tick=tick==STEP-1;
wire[15:0] complete={~c2,sweep[11:0]};
assign rows[0]=(row==0)?1'b0:1'bz;
assign rows[1]=(row==1)?1'b0:1'bz;
assign rows[2]=(row==2)?1'b0:1'bz;
assign rows[3]=(row==3)?1'b0:1'bz;
always @(posedge clk or posedge rst)begin
 if(rst)begin tick<=0;row<=0;c1<=15;c2<=15;ss<=0;sweep<=0;candidate<=0;stable<=16'hffff;debounce<=0;events<=0;tour_on<=0;tour_off<=0;switch_candidate<=0;switch_stable<=0;switch_debounce<=0;end
 else begin
 c1<=columns;c2<=c1;ss<={ss[0],tour_switch};events<=0;tour_on<=0;tour_off<=0;
 if(tick==STEP-1)begin
  tick<=0;row<=row+1'b1;
  case(row)0:sweep[3:0]<=~c2;1:sweep[7:4]<=~c2;2:sweep[11:8]<=~c2;3:begin
   if(complete!=candidate)begin candidate<=complete;debounce<=0;end
   else if(debounce<4)debounce<=debounce+1'b1;
   else if(candidate!=stable)begin
    stable<=candidate;
    if(stable==0 && candidate!=0 && (candidate&(candidate-1'b1))==0)events<=candidate;
   end
   if(ss[1]!=switch_candidate)begin switch_candidate<=ss[1];switch_debounce<=0;end
   else if(switch_debounce<4)switch_debounce<=switch_debounce+1'b1;
   else if(switch_stable!=switch_candidate)begin
    switch_stable<=switch_candidate;tour_on<=switch_candidate;tour_off<=!switch_candidate;
   end
  end endcase
 end else tick<=tick+1'b1;
 end
end
endmodule
