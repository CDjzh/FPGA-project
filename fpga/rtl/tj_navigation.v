// Six keys only: 0 confirm, 1 next, 2 previous, 3 back, 4 full-screen, 5 settings.
module tj_navigation #(parameter CLOCK_HZ=40000000)(input clk,rst,mounted,busy,loaded,finished,input[5:0] keys,input zoom_back,
 output reg[1:0] page,instrument,detail,output reg clip,output reg[2:0] focus,
 output reg paused,output reg[3:0] brightness,contrast,output reg settings,param_select,
 output reg zoom_mode,output reg start,output cancel,output reg auto_mode,output reg tour_intro,output reg ensemble_mode,output reg ensemble_cancel);
localparam CAROUSEL_CYCLES=(CLOCK_HZ/10)*79;
reg[28:0] carousel_timer;
reg[26:0] intro_timer;
localparam INTRO_CYCLES=(CLOCK_HZ/2)*3;
reg pending,booted,track_armed;reg[7:0] running;
assign cancel=busy&&pending&&({auto_mode,page,instrument,clip,detail}!=running);
always @(posedge clk or posedge rst)begin
 if(rst)begin zoom_mode<=0;page<=0;instrument<=0;detail<=0;clip<=0;focus<=0;paused<=0;brightness<=4;contrast<=4;start<=0;pending<=0;booted<=0;running<=0;auto_mode<=0;track_armed<=0;settings<=0;param_select<=0;carousel_timer<=0;tour_intro<=0;intro_timer<=0;ensemble_mode<=0;ensemble_cancel<=0;end
 else begin
  start<=0;
  if(ensemble_mode&&ensemble_cancel&&!busy)begin ensemble_mode<=0;ensemble_cancel<=0;page<=0;focus<=5;paused<=0;pending<=1;end
  if(!auto_mode)begin tour_intro<=0;intro_timer<=0;end
  else if(tour_intro&&!busy&&!pending&&!start&&loaded&&!finished&&!paused)begin
   if(intro_timer>=INTRO_CYCLES-1)begin tour_intro<=0;intro_timer<=0;end
   else intro_timer<=intro_timer+1'b1;
  end
  if(auto_mode&&!tour_intro&&!busy&&!pending&&!start)begin
   if(carousel_timer>=(CLOCK_HZ/40)*237)detail<=3;else if(carousel_timer>=(CLOCK_HZ/20)*79)detail<=2;else if(carousel_timer>=(CLOCK_HZ/40)*79)detail<=1;else detail<=0;
  end
  if(start||!auto_mode||tour_intro)carousel_timer<=0;
  else if(!busy&&!pending&&loaded&&track_armed&&!paused&&carousel_timer<CAROUSEL_CYCLES)carousel_timer<=carousel_timer+1'b1;
  if(start)track_armed<=0;
  else if(!busy&&!pending&&loaded&&!finished)track_armed<=1;
  if(!busy&&!start)begin
   if(!booted&&mounted)begin booted<=1;pending<=0;start<=1;running<={auto_mode,page,instrument,clip,detail};end
   else if(pending)begin start<=1;pending<=0;running<={auto_mode,page,instrument,clip,detail};end
  end
  if(auto_mode&&!tour_intro&&track_armed&&!busy&&!pending&&!start&&loaded&&(finished||carousel_timer>=CAROUSEL_CYCLES)&&!paused&&keys==0)begin
   instrument<=instrument+1'b1;clip<=1;detail<=0;pending<=1;tour_intro<=1;intro_timer<=0;
  end
  if(keys[5]&&!zoom_mode)begin settings<=~settings;param_select<=0;end
  else if(settings)begin
   if(keys[3])settings<=0;
   else if(keys[0])param_select<=~param_select;
   else if(keys[1]||keys[2])begin
    if(param_select)begin if(keys[1]&&contrast<8)contrast<=contrast+1'b1;else if(keys[2]&&contrast>0)contrast<=contrast-1'b1;end
    else begin if(keys[1]&&brightness<8)brightness<=brightness+1'b1;else if(keys[2]&&brightness>0)brightness<=brightness-1'b1;end
   end
  end else if(zoom_mode)begin
   if(zoom_back===1'b1)begin zoom_mode<=0;page<=1;focus<=4;pending<=1;end
  end else if(ensemble_mode)begin
   if(keys[3]&&busy)begin ensemble_cancel<=1;paused<=1;end
   if(!busy)begin
    if(keys[3])begin ensemble_mode<=0;page<=0;focus<=5;paused<=0;pending<=1;end
    else if(keys[0])begin if(finished)begin paused<=0;pending<=1;end else paused<=~paused;end
   end
  end else if(keys[3])begin
   auto_mode<=0;paused<=0;tour_intro<=0;intro_timer<=0;
   if(page==2)begin page<=1;focus<=2;pending<=1;end
   else if(page==3&&!auto_mode)begin page<=1;focus<=3;pending<=1;end
   else begin page<=0;focus<={1'b0,instrument};pending<=1;end
  end else if(keys[4]&&!auto_mode)begin
   page<=(page==3)?1:3;paused<=0;pending<=1;
  end else if(keys[1]||keys[2])begin
   if(page==0)begin
    if(keys[1])begin focus<=(focus==5)?0:focus+1'b1;if(focus==5)instrument<=0;else if(focus<3)instrument<=instrument+1'b1;end
    else begin focus<=(focus==0)?5:focus-1'b1;if(focus!=0)instrument<=(focus>=4)?3:instrument-1'b1;end
   end else if(page==1)focus<=keys[1]?((focus==4)?0:focus+1'b1):((focus==0)?4:focus-1'b1);
   else if(page==2)begin detail<=keys[1]?((detail==2)?0:detail+1'b1):((detail==0)?2:detail-1'b1);pending<=1;end
   else begin if(auto_mode)begin tour_intro<=1;intro_timer<=0;end instrument<=keys[1]?instrument+1'b1:instrument-1'b1;detail<=0;paused<=0;pending<=1;end
  end else if(keys[0])begin
   if(page==0)begin
    if(focus==5)begin page<=3;ensemble_mode<=1;ensemble_cancel<=0;auto_mode<=0;clip<=1;paused<=0;pending<=1;end
    else if(focus==4)begin page<=3;instrument<=0;clip<=1;detail<=0;auto_mode<=1;paused<=0;pending<=1;tour_intro<=1;intro_timer<=0;end
    else begin page<=1;clip<=0;focus<=0;paused<=0;pending<=1;end
   end else if(page==2)begin page<=1;focus<=2;pending<=1;end
   else if(page==3)begin if(finished&&!auto_mode)begin paused<=0;pending<=1;end else paused<=~paused;end
   else case(focus)
    0,1:begin if(clip==focus[0]&&loaded&&!finished)paused<=~paused;
     else begin clip<=focus[0];paused<=0;pending<=1;end end
    2:begin page<=2;detail<=0;pending<=1;end
    3:begin page<=3;paused<=0;pending<=1;end
    4:begin zoom_mode<=1;paused<=1;end
   endcase
  end
 end
end
endmodule
