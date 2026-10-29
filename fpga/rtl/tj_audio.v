// Audio clock defines exact 48 kHz cadence. Stable-data/toggle CDC to pixel clock.
module tj_audio(input audio_clk,pixel_clk,rst,input enable,paused,short_clip,packed_pcm,input[21:0] length,
 input fifo_empty,input fifo_valid,input[31:0] fifo_data,output fifo_re,
 output reg sample_valid,output reg[23:0] sample_data,output reg[21:0] position,
 output playing,output reg underrun);
reg[7:0] divider;reg tick_toggle;
(* async_reg="true" *)reg[2:0] tick_sync;reg tick_last;
(* async_reg="true" *)reg[1:0] enable_sync,pause_sync;
wire[21:0] remaining=length-position;
wire[9:0] envelope=(position<512)?{1'b0,position[8:0]}:((remaining<512)?{1'b0,remaining[8:0]}:10'd512);
reg high_half,pending_high;reg[15:0] high_sample;
wire signed[15:0] raw_sample=pending_high?high_sample:fifo_data[15:0];
wire signed[26:0] soft_sample=$signed(raw_sample)*$signed({1'b0,envelope});
reg pending,pending_read,pending_starved,armed;wire tick=tick_sync[2]^tick_last;
assign playing=enable_sync[1]&&armed&&!pause_sync[1]&&position<length;
assign fifo_re=tick&&playing&&(!high_half||!(packed_pcm===1'b1))&&!fifo_empty;
always @(posedge audio_clk or posedge rst)if(rst)begin divider<=0;tick_toggle<=0;end
 else begin divider<=divider+1'b1;if(divider==255)tick_toggle<=~tick_toggle;end
always @(posedge pixel_clk or posedge rst)begin
 if(rst)begin tick_sync<=0;tick_last<=0;enable_sync<=0;pause_sync<=0;high_half<=0;pending_high<=0;high_sample<=0;pending<=0;pending_read<=0;pending_starved<=0;armed<=0;sample_valid<=0;sample_data<=0;position<=0;underrun<=0;end
 else begin
 tick_sync<={tick_sync[1:0],tick_toggle};tick_last<=tick_sync[2];
 enable_sync<={enable_sync[0],enable};pause_sync<={pause_sync[0],paused};
 pending<=tick;pending_read<=fifo_re;pending_high<=tick&&playing&&(packed_pcm===1'b1)&&high_half;pending_starved<=tick&&playing&&fifo_empty&&!high_half;sample_valid<=pending;
 if(!enable_sync[1])begin position<=0;underrun<=0;armed<=0;high_half<=0;end
 else if(!fifo_empty)armed<=1;
 if(pending)begin
  if(((fifo_valid&&pending_read)||pending_high)&&enable_sync[1])begin
   if(packed_pcm===1'b1)begin high_half<=~high_half;if(pending_read)high_sample<=fifo_data[31:16];end sample_data<=short_clip?{soft_sample[24:9],8'd0}:{raw_sample,8'd0};position<=position+1'b1;end
  else begin sample_data<=0;if(pending_starved)underrun<=1;end
 end
 end
end
endmodule
