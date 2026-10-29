// Six direct controls; hold KEY5 for0.8s to return without a seventh key.
module tj_zoom_control #(parameter CLOCK_HZ=40000000)(input clk,rst,enable,input[1:0] instrument,input[5:0] keys,held,input ms_tick,
 output[1:0] field,output reg back,output reg[2:0] level,output reg[10:0] x,y);
assign field=2'd2;
// One arithmetic unit updates X then Y over two clocks. Human key events
// are milliseconds apart, so this saves logic without visible latency.
function[5:0] pan_x;input[2:0] z;begin case(z)0:pan_x=42;1:pan_x=31;2:pan_x=21;3:pan_x=15;default:pan_x=10;endcase end endfunction
function[5:0] pan_y;input[2:0] z;begin case(z)0:pan_y=36;1:pan_y=27;2:pan_y=18;3:pan_y=13;default:pan_y=9;endcase end endfunction
function[10:0] max_x;input[2:0] z;begin case(z)0:max_x=944;1:max_x=1028;2:max_x=1112;3:max_x=1154;default:max_x=1196;endcase end endfunction
function[10:0] max_y;input[2:0] z;begin case(z)0:max_y=672;1:max_y=744;2:max_y=816;3:max_y=852;default:max_y=888;endcase end endfunction
reg[1:0] phase;reg[2:0] target_level;reg signed[7:0] delta_x,delta_y;reg[10:0] pending_x;
wire[10:0] coordinate=phase==1?x:y;
wire signed[7:0] delta=phase==1?delta_x:delta_y;
wire[10:0] limit=phase==1?max_x(target_level):max_y(target_level);
wire signed[12:0] sum=$signed({2'b0,coordinate})+$signed(delta);
wire[10:0] bounded=sum<0?11'd0:sum>$signed({2'b0,limit})?limit:sum[10:0];
reg[9:0] hold_count;reg back_sent;
wire[10:0] initial_x=(instrument==1)?242:(instrument==2)?352:(instrument==3)?312:472;
wire[10:0] initial_y=(instrument==1)?416:(instrument==2)?656:(instrument==3)?386:156;
always @(posedge clk or posedge rst)begin
 if(rst)begin level<=0;x<=472;y<=156;back<=0;hold_count<=0;back_sent<=0;phase<=0;target_level<=0;delta_x<=0;delta_y<=0;pending_x<=0;end
 else begin
  back<=0;
  if(!enable)begin level<=0;x<=initial_x;y<=initial_y;hold_count<=0;back_sent<=0;phase<=0;target_level<=0;delta_x<=0;delta_y<=0;end
  else begin
   case(phase)
   0:if(|keys)begin
    target_level<=level;delta_x<=0;delta_y<=0;phase<=1;
    if(keys[4]&&level<4)begin target_level<=level+1'b1;delta_x<=level<2?42:21;delta_y<=level<2?36:18;end
    else if(keys[5]&&level>0)begin target_level<=level-1'b1;delta_x<=level<3?-42:-21;delta_y<=level<3?-36:-18;end
    else if(keys[0])delta_y<=-$signed({2'b0,pan_y(level)});
    else if(keys[1])delta_y<=$signed({2'b0,pan_y(level)});
    else if(keys[2])delta_x<=-$signed({2'b0,pan_x(level)});
    else if(keys[3])delta_x<=$signed({2'b0,pan_x(level)});
   end
   1:begin pending_x<=bounded;phase<=2;end
   2:begin x<=pending_x;y<=bounded;level<=target_level;phase<=0;end
   default:phase<=0;
   endcase
   if(held[5]===1'b1)begin
    if(!back_sent&&ms_tick)begin
     if(hold_count>=799)begin back<=1;back_sent<=1;end
     else hold_count<=hold_count+1'b1;
    end
   end else begin hold_count<=0;back_sent<=0;end
  end
 end
end
endmodule
