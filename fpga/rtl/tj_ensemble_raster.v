// Cached photograph compositor. All geometry and animation are computed by FPGA.
// Shared line cache:600px foreground/portraits OR magnifier source/overview.
module tj_ensemble_raster #(parameter VIDEO_HIGH=440,HD_ROWS=480)(input clk,rst,enable,loaded,input[21:0] position,
 input zoom_mode,input[10:0] zoom_x,zoom_y,input[2:0] zoom_level,
 input read_req,output reg read_ack,output reg video_clear,output video_we,output[31:0] video_data,input[9:0] video_used,
 output mem_req,output[20:0] mem_addr,output[6:0] mem_count,input mem_accept,mem_valid,input[31:0] mem_data,
 output reg[2:0] stage,output reg[6:0] anim_step,output reg fault);
`include "@PROJECT_ROOT@/rtl/tj_ensemble_geometry.vh"
function[9:0] tile_x;input[2:0] k;begin case(k)0,2:tile_x=16;1,3:tile_x=432;default:tile_x=224;endcase end endfunction
function[8:0] tile_y;input[2:0] k;begin case(k)0,1:tile_y=60;2,3:tile_y=236;default:tile_y=154;endcase end endfunction
function[21:0] cue;input[2:0] k;begin case(k)1:cue=426667;2:cue=853333;3:cue=1280000;4:cue=1702841;default:cue=0;endcase end endfunction
wire[2:0] live_stage=(position>=1702841)?4:(position>=1280000)?3:(position>=853333)?2:(position>=426667)?1:0;
reg[21:0] frame_position,frame_age;reg[16:0] step_remainder;
wire[79:0] geom=geometry(anim_step);
wire[9:0] width=geom[79:70];wire[8:0] height=geom[69:61];
wire[17:0] xfactor=geom[60:43],yfactor=geom[42:25];
// Geometry is fixed for a frame. Register its origin during the request
// handshake, before row reads, to avoid cascading division and two source
// address multipliers on the same 40 MHz clock path.
reg[9:0] left;reg[8:0] top;
reg zoom_frame;reg[10:0] zx,zy;reg[2:0] zl;
function[10:0] zwidth;input[2:0] z;begin case(z)0:zwidth=336;1:zwidth=252;2:zwidth=168;3:zwidth=126;default:zwidth=84;endcase end endfunction
function[10:0] zmap;input[9:0] v;input[2:0] z;begin case(z)0:zmap=v;1:zmap=(v*3)/4;2:zmap=v/2;3:zmap=(v*3)/8;default:zmap=v/4;endcase end endfunction

(* async_reg="true" *)reg[2:0] req_sync;
reg[3:0] state;reg[8:0] y;reg[10:0] physical_row;reg[3:0] row_fraction;reg[9:0] x;reg[2:0] scan;
// Declare raster coordinates before use and explicitly size both deltas.
wire[8:0] zoom_dy=y-9'd88;
wire[9:0] zoom_dx=x-10'd288;
wire[10:0] zoom_source_y=zy+zmap({1'b0,zoom_dy},zl);
wire[10:0] zoom_source_x=zmap(zoom_dx,zl)+zx[0];
reg[20:0] address;reg[8:0] remaining;reg[9:0] cache_write;reg[6:0] received;
reg[31:0] cache[0:1023];reg[31:0] cache_q;reg select_half;reg pixel_photo;reg[23:0] background;
reg[15:0] timeout;
wire[8:0] column_room=256-{1'b0,address[7:0]};
wire[6:0] burst=(remaining<64)?remaining[6:0]:7'd64;
assign mem_req=state==4;assign mem_addr=address;assign mem_count=(column_room<burst)?column_room[6:0]:burst;
wire in_foreground=loaded&&anim_step<96&&x>=left&&x<left+width&&y>=top&&y<top+height;
wire[9:0] foreground_dx=x-left;
wire[8:0] foreground_dy=y-top;
wire[27:0] foreground_sx=foreground_dx*xfactor;
wire[26:0] foreground_sy=foreground_dy*yfactor;
reg[8:0] source_row;
reg[10:0] zoom_row;
reg[10:0] pixel_index;reg found;integer k;
always @*begin
 pixel_index=0;found=0;
 for(k=0;k<5;k=k+1)if(loaded&&(k<stage||(k==stage&&anim_step==96))&&x>=tile_x(k)&&x<tile_x(k)+192&&y>=tile_y(k)&&y<tile_y(k)+144)begin
  pixel_index=600+k*192+(x-tile_x(k));found=1;
 end
 if(in_foreground)begin pixel_index=foreground_sx[26:16];found=1;end
 if(zoom_frame)begin
  found=0;pixel_index=0;
  if(loaded&&y>=104&&y<272&&x>=16&&x<240)begin found=1;pixel_index=1280+x-16;end
  if(loaded&&y>=88&&y<376&&x>=288&&x<624)begin found=1;pixel_index=zoom_source_x;end
 end
end
wire emit=state==7&&video_used<VIDEO_HIGH;
reg emit_previous;reg load_foreground;
// Read only the visible part of a settled portrait when the incoming image
// covers part of its row. Native thumbnails must not increase FIFO stalls.
reg[6:0] tile_first,tile_end;
always @*begin
 tile_first=0;tile_end=96;
 if(anim_step<96&&y>=top&&y<top+height)begin
  if(left<=tile_x(scan)&&left+width>tile_x(scan))tile_first=(left+width-tile_x(scan))/2;
  if(left>tile_x(scan)&&left<tile_x(scan)+192&&left+width>=tile_x(scan)+192)tile_end=(left-tile_x(scan)+1)/2;
 end
 if(tile_first>96)tile_first=96;
end
wire[15:0] pixel=select_half?cache_q[31:16]:cache_q[15:0];
assign video_we=emit_previous;
assign video_data=pixel_photo?{pixel[15:11],pixel[15:13],pixel[10:5],pixel[10:9],pixel[4:0],pixel[4:2],8'd0}:{background,8'd0};
always @(posedge clk)begin
 if(mem_valid&&state==5)cache[cache_write+received]<=mem_data;
 if(emit)begin cache_q<=cache[pixel_index[10:1]];select_half<=pixel_index[0];pixel_photo<=found;background<=24'hf4f1e8;end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin req_sync<=0;state<=0;y<=0;physical_row<=0;row_fraction<=0;x<=0;scan<=0;address<=0;remaining<=0;cache_write<=0;received<=0;read_ack<=0;video_clear<=1;emit_previous<=0;stage<=0;anim_step<=0;timeout<=0;fault<=0;load_foreground<=0;left<=0;top<=0;zoom_frame<=0;zx<=0;zy<=0;zl<=0;frame_position<=0;frame_age<=0;step_remainder<=0;source_row<=0;zoom_row<=0;end
 else begin
 req_sync<={req_sync[1:0],read_req};emit_previous<=emit;
 if(!enable)begin state<=0;read_ack<=0;video_clear<=1;emit_previous<=0;end
 else case(state)
 0:if(req_sync[2])begin
  state<=9;read_ack<=1;video_clear<=1;stage<=live_stage;frame_position<=position;y<=0;physical_row<=0;row_fraction<=0;x<=0;zoom_frame<=zoom_mode===1'b1;zx<=zoom_x;zy<=zoom_y;zl<=zoom_level;
 end
 // Exact floor((age-28800)/800), time-shared across at most96 blanking
 // clocks rather than a long combinational divider after the CDC decoder.
 9:begin frame_age<=frame_position-cue(stage);state<=10;end
 10:begin
  anim_step<=0;
  if(zoom_frame||frame_age<28800)state<=1;
  else if(frame_age>=105600)begin anim_step<=96;state<=1;end
  else begin step_remainder<=frame_age[16:0]-17'd28800;state<=11;end
 end
 11:if(step_remainder>=800)begin step_remainder<=step_remainder-17'd800;anim_step<=anim_step+1'b1;end else state<=1;
 1:begin
  left<=(tile_x(stage)*anim_step)/96;top<=(tile_y(stage)*anim_step)/96;
  if(!req_sync[2])begin read_ack<=0;video_clear<=0;scan<=0;state<=2;end
 end
 2:begin
  if(zoom_frame)begin
   if(scan==0&&loaded&&y>=104&&y<272)begin address<=614400+(y-104)*112;remaining<=112;cache_write<=640;load_foreground<=0;scan<=5;state<=4;end
   else state<=3;
  end else if(scan==5)state<=3;
  else if(loaded&&(scan<stage||(scan==stage&&anim_step==96))&&y>=tile_y(scan)&&y<tile_y(scan)+144&&!(anim_step<96&&y>=top&&y<top+height&&left<=tile_x(scan)&&left+width>=tile_x(scan)+192))begin
   address<=675000+scan*13824+(y-tile_y(scan))*96+tile_first;remaining<=tile_end-tile_first;load_foreground<=0;cache_write<=300+scan*96+tile_first;scan<=scan+1'b1;state<=4;
  end else scan<=scan+1'b1;
 end
 3:if(zoom_frame)begin
  if(loaded&&y>=88&&y<376)begin zoom_row<=zoom_source_y;state<=12;end
  else begin x<=0;state<=7;end
 end else if(loaded&&anim_step<96&&y>=top&&y<top+height)begin
  source_row<=foreground_sy[24:16];state<=13;
 end else begin x<=0;state<=7;end
 12:begin address<=zoom_row*21'd640+(zx>>1);remaining<=(zwidth(zl)+zx[0]+1)>>1;load_foreground<=1;cache_write<=0;state<=4;end
 13:begin address<=stage*21'd135000+source_row*21'd300;remaining<=300;load_foreground<=1;cache_write<=0;state<=4;end
 4:if(mem_accept)begin received<=0;timeout<=0;state<=5;end
 5:begin
  timeout<=timeout+1'b1;
  if(mem_valid)begin
   received<=received+1'b1;
   if(received+1==mem_count)begin address<=address+mem_count;cache_write<=cache_write+mem_count;remaining<=remaining-mem_count;state<=6;end
  end
  if(&timeout)begin fault<=1;state<=0;end
 end
 6:if(remaining!=0)state<=4;else if(load_foreground)begin x<=0;state<=7;end else state<=2;
 7:if(emit)begin if(x==639)begin x<=0;state<=8;end else x<=x+1'b1;end
 8:begin
  if(physical_row==HD_ROWS-1)state<=0;
  else begin
   physical_row<=physical_row+1'b1;
   if(HD_ROWS==480)y<=y+1'b1;
   else if(row_fraction+4>=9)begin row_fraction<=row_fraction-5;y<=y+1'b1;end
   else row_fraction<=row_fraction+4;
   // Repeated HD scanlines share exactly the same geometry and source row.
   // Keep the completed line cache instead of fetching it from SDRAM again.
   scan<=0;x<=0;
   if(HD_ROWS!=480&&row_fraction+4<9)state<=7;else state<=2;
  end
 end
 default:state<=0;
 endcase
 end
end
endmodule
