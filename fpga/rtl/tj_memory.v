// SDRAM arbiter: bounded video/audio read bursts; acknowledged single writes.
// A burst owns all returned words until its final response, avoiding owner races.
module tj_memory #(parameter VIDEO_LOW=384,VIDEO_HIGH=448,HD_ROWS=480)(input clk,rst,input init_done,refresh,busy,
 input read_req,output reg read_ack,input[4:0] frame_index,output reg[4:0] frame_used,input video_suspend,
 output reg video_clear,output video_we,output[31:0] video_data,input[9:0] video_used,
 input stream_mode,input[23:0] stream_produced,output reg[23:0] stream_consumed,
 input audio_enable,packed_pcm,input[20:0] audio_base,input[21:0] audio_length,output audio_clear,output audio_we,
 output[31:0] audio_data,input[9:0] audio_used,
 input wr_valid,output wr_ready,input[20:0] wr_addr,input[31:0] wr_data,
 output app_we,output[20:0] app_wa,output[31:0] app_wd,
 output app_re,output[20:0] app_ra,output[6:0] app_count,input rd_valid,input[31:0] rd_data,output reg fault,
 input ens_request,input[20:0] ens_address,input[6:0] ens_count,output ens_accept,output ens_valid,output[31:0] ens_data);
(* async_reg="true" *)reg[2:0] request_sync;
reg[2:0] state;reg[1:0] owner;reg[6:0] issued,received,count;reg[20:0] addr,vaddr;
reg[19:0] vleft;reg[21:0] aleft;reg[20:0] aaddr;reg[15:0] timeout;reg aold;reg[4:0] reset_hold;
// R19: a frame-latched 24-frame old/new horizontal reveal. Only one
// source is read per output row, so SDRAM bandwidth does not double.
reg[8:0] raster_y;reg[10:0] physical_row;reg[3:0] row_fraction;reg[20:0] normal_base;
reg[4:0] target_frame,old_frame;
reg[8:0] wipe_rows;
reg row_pending;
function[20:0] picture_base;input[4:0] f;begin
 picture_base=((f-8)>>2)*333600+((f[1:0]==0)?0:(153600+(f[1:0]-1)*60000));
end endfunction
wire[4:0] row_frame=(raster_y<wipe_rows)?target_frame:old_frame;
wire row_full=row_frame[1:0]==0;
wire[20:0] row_address=picture_base(row_frame)+(row_full?(raster_y*320):(((raster_y*5)>>3)*200));
// Streaming writes must receive a bounded service slot between raster bursts.
// A pending write can win once; the next competing raster request wins.
reg stream_write_turn;
wire stream_write_priority=(stream_mode===1'b1)&&wr_valid&&stream_write_turn;
reg compact;reg[9:0] raster_word;reg full_size;
reg[31:0] line_buffer[0:63];reg[7:0] drain_half;reg[2:0] phase;reg[6:0] drain_words;
wire[3:0] next_phase={1'b0,phase}+(full_size?8:5);
wire[9:0] source_row_words=full_size?320:200;
wire[15:0] packed_pixel=drain_half[0]?line_buffer[drain_half[7:1]][31:16]:line_buffer[drain_half[7:1]][15:0];
wire[23:0] expanded_pixel={packed_pixel[15:11],packed_pixel[15:13],packed_pixel[10:5],packed_pixel[10:9],packed_pixel[4:0],packed_pixel[4:2]};
wire[19:0] ring_next=aaddr[19:0]+count;
wire audio_need=audio_enable&&reset_hold==0&&((stream_mode===1'b1)?(stream_produced>stream_consumed):(aleft!=0))&&audio_used<256;
wire video_need=vleft!=0&&video_used<VIDEO_LOW&&!request_sync[2]&&!(video_suspend===1'b1);
// SDRAM full-page bursts wrap at column255, never into the next bank/row.
function[6:0] bounded_count;input[20:0] address;input[21:0] remaining;reg[8:0] room;begin
 room=9'd256-{1'b0,address[7:0]};
 bounded_count=(remaining<64)?remaining[6:0]:7'd64;
 if(room<bounded_count)bounded_count=room[6:0];
end endfunction
wire[19:0] video_remaining=compact?(source_row_words-raster_word):((HD_ROWS==480)?vleft:(640-raster_word));
assign audio_clear=rst||!audio_enable||reset_hold!=0;
assign video_we=(state==2&&!owner&&!compact&&rd_valid)||(state==5&&video_used<VIDEO_HIGH);
assign audio_we=state==2&&owner==1&&rd_valid&&audio_enable;
assign video_data=(state==5)?{expanded_pixel,8'd0}:rd_data;assign audio_data=rd_data;
// Refresh can become due after arbitration but before the first READ edge.
// Keep the starting address intact until the controller can accept that edge.
assign app_re=state==2&&issued<count&&(issued!=0||(!busy&&!refresh));
assign ens_accept=state==0&&init_done&&!refresh&&!busy&&!request_sync[2]&&!audio_need&&!stream_write_priority&&(ens_request===1'b1);
assign ens_valid=state==2&&owner==2&&rd_valid;assign ens_data=rd_data;
assign app_count=count;
assign app_ra=addr;assign app_wa=wr_addr;assign app_wd=wr_data;
assign wr_ready=state==0&&init_done&&!refresh&&!busy&&!request_sync[2]&&!video_need&&!audio_need&&(!(ens_request===1'b1)||stream_write_priority);
assign app_we=wr_valid&&wr_ready;
always @(posedge clk or posedge rst)begin
 if(rst)begin stream_write_turn<=1;target_frame<=0;old_frame<=0;wipe_rows<=480;row_pending<=0;compact<=0;full_size<=0;raster_y<=0;physical_row<=0;row_fraction<=0;normal_base<=0;raster_word<=0;drain_half<=0;phase<=0;drain_words<=0;request_sync<=0;state<=0;owner<=0;issued<=0;received<=0;count<=0;addr<=0;vaddr<=0;vleft<=0;aleft<=0;aaddr<=1048576;read_ack<=0;frame_used<=0;video_clear<=1;timeout<=0;aold<=0;reset_hold<=16;fault<=0;stream_consumed<=0;end
 else begin
 request_sync<={request_sync[1:0],read_req};aold<=audio_enable;
 if(!(stream_mode===1'b1))stream_write_turn<=1;
 else if(app_we)stream_write_turn<=0;
 else if(ens_accept)stream_write_turn<=1;
 if(!audio_enable)begin stream_consumed<=0;reset_hold<=16;aleft<=(packed_pcm===1'b1)?((audio_length+1)>>1):audio_length;aaddr<=audio_base;end
 else if(reset_hold!=0)begin stream_consumed<=0;reset_hold<=reset_hold-1'b1;aleft<=(packed_pcm===1'b1)?((audio_length+1)>>1):audio_length;aaddr<=audio_base;end
 case(state)
 0:begin
  timeout<=0;
  if(init_done&&!refresh&&!busy)begin
   if(request_sync[2])begin read_ack<=1;frame_used<=frame_index;video_clear<=1;state<=1;
    case(frame_index)
     0:begin vaddr<=0;normal_base<=0;end
     1:begin vaddr<=307200;normal_base<=307200;end
     2:begin vaddr<=614400;normal_base<=614400;end
     3:begin vaddr<=921600;normal_base<=921600;end
     default:begin vaddr<=1228800;normal_base<=1228800;end
    endcase
    physical_row<=0;row_fraction<=0;raster_y<=0;raster_word<=0;row_pending<=0;
    if(frame_index>=8)begin
     compact<=1;target_frame<=frame_index;
     if(!compact)begin old_frame<=frame_index;wipe_rows<=480;end
     else if(frame_index!=target_frame)begin old_frame<=target_frame;wipe_rows<=(HD_ROWS==480)?20:40;end
     else if(wipe_rows<480)wipe_rows<=wipe_rows+((HD_ROWS==480)?20:40);
     // The first row is always from the incoming picture.
     full_size<=frame_index[1:0]==0;vaddr<=picture_base(frame_index);
     vleft<=HD_ROWS;raster_y<=0;raster_word<=0;phase<=0;row_pending<=0;
    end
    else begin compact<=0;vleft<=(HD_ROWS==480)?307200:HD_ROWS;end
   end else if(audio_need)begin owner<=1;addr<=aaddr;count<=bounded_count(aaddr,(stream_mode===1'b1)?(stream_produced-stream_consumed):aleft);issued<=0;received<=0;state<=2;end
   else if(ens_request===1'b1&&!stream_write_priority)begin owner<=2;addr<=ens_address;count<=ens_count;issued<=0;received<=0;state<=2;end
   else if(video_need)begin owner<=0;addr<=vaddr;count<=bounded_count(vaddr,video_remaining);issued<=0;received<=0;state<=2;end
  end
 end
 1:if(!request_sync[2])begin read_ack<=0;video_clear<=0;state<=0;end
 2:begin
   timeout<=timeout+1'b1;
   if(app_re)begin issued<=issued+1'b1;addr<=addr+1'b1;end
   if(rd_valid)begin received<=received+1'b1;
    if(!owner&&compact)line_buffer[received]<=rd_data;
    if(received+1==count)begin
     state<=3;
     if(owner==1)begin if(stream_mode===1'b1)begin aaddr<={1'b1,ring_next};stream_consumed<=stream_consumed+count;end else begin aaddr<=aaddr+count;aleft<=aleft-count;end end
     else if(owner==0)begin
      if(!compact&&HD_ROWS==480)vleft<=vleft-count;
      if(compact)begin state<=5;drain_half<=0;drain_words<=count;
       if(raster_word+count==source_row_words)begin
        raster_word<=0;row_pending<=1;physical_row<=physical_row+1'b1;
        if(HD_ROWS==480)raster_y<=raster_y+1'b1;
        else if(row_fraction+4>=9)begin row_fraction<=row_fraction-5;raster_y<=raster_y+1'b1;end
        else row_fraction<=row_fraction+4;
        if(physical_row==HD_ROWS-1)vleft<=0;
       end
       else begin raster_word<=raster_word+count;vaddr<=vaddr+count;end
      end else if(HD_ROWS==480)vaddr<=vaddr+count;
      else if(raster_word+count==640)begin
       raster_word<=0;row_pending<=1;physical_row<=physical_row+1'b1;
       if(row_fraction+4>=9)begin row_fraction<=row_fraction-5;raster_y<=raster_y+1'b1;end
       else row_fraction<=row_fraction+4;
       if(physical_row==HD_ROWS-1)vleft<=0;
      end else begin raster_word<=raster_word+count;vaddr<=vaddr+count;end
     end
    end
   end
   if(&timeout)begin fault<=1;state<=4;end
 end
 5:if(video_used<VIDEO_HIGH)begin
 phase<=next_phase[2:0];
 if(next_phase>=8)begin drain_half<=drain_half+1'b1;if(drain_half+1=={drain_words,1'b0})state<=3;end
 end
 3:begin
   // Change the row source only AFTER the last pixel has left its drain.
   // Updating full_size while draining would change its scaling ratio.
   if(row_pending)begin full_size<=row_full;vaddr<=compact?row_address:(normal_base+raster_y*21'd640);phase<=0;row_pending<=0;end
   state<=0;
 end // turn-around cycle, including the final FIFO write
 4:state<=4;
 endcase
 end
end
endmodule
