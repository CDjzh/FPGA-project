module top(input clk,rst_n,input[3:0] key_col,output[3:0] key_row,output[3:0] status_led,
 output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,
 output sd_ncs,sd_dclk,sd_mosi,input sd_miso);
wire ens_loaded,mix_panel,normal_audio_re,special_video;wire[21:0] position_mem;
wire ensemble_mode,ensemble_cancel,zoom_mode;wire[21:0] audio_position;wire[31:0] file_sector,file_word;wire[6:0] file_wa;
wire sd_card_clk,ext_mem_clk,ext_mem_clk_sft,video_clk,ui_clk,hdmi_5x_clk,audio_mclk,audio_pll_lock;
wire rst_all=~rst_n|~audio_pll_lock;
sys_pll sys_pll_m0(.refclk(clk),.clk0_out(sd_card_clk),.clk1_out(ext_mem_clk),.clk2_out(ext_mem_clk_sft),.reset(1'b0));
video_pll video_pll_m0(.refclk(clk),.clk0_out(video_clk),.clk1_out(hdmi_5x_clk),.clk2_out(ui_clk),.reset(1'b0));
PLL_HDMI_AUDIO u_audio_pll(.refclk(clk),.reset(1'b0),.extlock(audio_pll_lock),.clk0_out(),.clk1_out(),.clk2_out(audio_mclk));

wire card_ready,sd_req,sd_valid,sd_end;wire[31:0] sd_lba;wire[7:0] sd_byte;
sd_card_top #(.SPI_LOW_SPEED_DIV(98),.SPI_HIGH_SPEED_DIV(0)) card(
 .clk(ext_mem_clk),.rst(rst_all),.SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso),
 .sd_init_done(card_ready),.sd_sec_read(sd_req),.sd_sec_read_addr(sd_lba),.sd_sec_read_data(sd_byte),.sd_sec_read_data_valid(sd_valid),.sd_sec_read_end(sd_end),
 .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end());
wire file_req,file_ready,mounted,file_idle;
wire normal_file_req,ens_file_req,stream_file_req,zoom_file_req;wire[31:0] stream_file_sector,zoom_file_sector,stream_base_sector;wire[6:0] stream_file_wa,zoom_file_wa;wire stream_select;wire[31:0] normal_file_sector,ens_file_sector;wire[6:0] normal_file_wa,ens_file_wa;
assign stream_select=1'b0;
// Transfer file-buffer ownership only after the outstanding SD/FAT request
// has completed AND its ready handshake was released. Never consume a late
// sector from the previous mode as the new mode's requested sector.
reg[1:0] file_owner;wire[1:0] desired_owner=zoom_mode?3:ensemble_mode?1:0;
reg[1:0] previous_file_owner;reg file_owner_valid;
wire file_available=file_owner_valid&&previous_file_owner==desired_owner&&file_owner==desired_owner;
always @(posedge ext_mem_clk or posedge rst_all)begin
 if(rst_all)begin file_owner<=0;previous_file_owner<=0;file_owner_valid<=0;end
 else begin
  previous_file_owner<=desired_owner;
  // Remember cancellation even if the user returns to the same mode before
  // its old physical SD transaction finishes. A new request needs fresh IDLE.
  if(previous_file_owner!=desired_owner)file_owner_valid<=0;
  else if(file_idle)begin file_owner<=desired_owner;file_owner_valid<=1;end
 end
end
assign file_req=file_available&&((file_owner==3)?zoom_file_req:(file_owner==1)?ens_file_req:normal_file_req);
assign file_sector=(file_owner==3)?zoom_file_sector:(file_owner==1)?ens_file_sector:normal_file_sector;
assign file_wa=(file_owner==3)?zoom_file_wa:(file_owner==1)?ens_file_wa:normal_file_wa;
wire[7:0] fs_error,media_error;
tj_sd_file filesystem(.clk(ext_mem_clk),.rst(rst_all),.card_ready(card_ready),.sd_req(sd_req),.sd_lba(sd_lba),.sd_byte(sd_byte),.sd_valid(sd_valid),.sd_end(sd_end),
 .req(file_req),.file_sector(file_sector),.ready(file_ready),.mounted(mounted),.idle(file_idle),.word_addr(file_wa),.word_data(file_word),.error(fs_error));
wire start;wire media_busy,media_done,frame_ready,audio_loaded,normal_audio_loaded;wire[19:0] normal_audio_samples;wire[21:0] audio_samples;wire[4:0] frame_index;wire[20:0] audio_base,normal_audio_base;
assign audio_base=ensemble_mode?21'd744120:normal_audio_base;wire[4:0] preload_progress;
wire[1:0] page,instrument,detail;wire clip;wire[2:0] focus;wire paused;wire[3:0] brightness,contrast;wire auto_mode,cancel,settings,param_select,tour_intro;
wire ens_busy,stream_warm,stream_fault,zoom_loaded;wire[7:0] zoom_error;wire[4:0] zoom_progress;wire[23:0] stream_produced,stream_consumed;wire[7:0] ens_error;wire[4:0] ens_progress;
// Dispatch depends on actual loader activity, never on the result of a not-yet-dispatched request.
wire navigation_busy=zoom_mode?(!zoom_loaded):ensemble_mode?ens_busy:media_busy;
wire display_busy=zoom_mode?(!zoom_loaded&&zoom_error==0):ensemble_mode?ens_busy:media_busy;
assign audio_loaded=ensemble_mode?ens_loaded:normal_audio_loaded;assign audio_samples=ensemble_mode?22'd2640000:{2'b0,normal_audio_samples};
reg has_frame;reg[6:0] loading_ui;reg[1:0] shown_page,shown_instrument,shown_detail;reg shown_clip;
reg ram_retry;wire bist_failed;
wire audio_finished;
wire video_ack;wire[4:0] frame_used;
reg ack_previous;reg[6:0] buffer_ui[0:31];
wire[15:0] key_events,key_held;wire zoom_back,key_ms_tick;
tj_keypad keypad(.clk(ext_mem_clk),.rst(rst_all),.columns(key_col),.rows(key_row),.tour_switch(1'b0),.events(key_events),.held(key_held),.ms_tick(key_ms_tick),.tour_on(),.tour_off());
tj_navigation navigation(.clk(ext_mem_clk),.rst(rst_all),.mounted(mounted),.busy(navigation_busy),.loaded(audio_loaded),.finished(audio_finished),.keys((mix_panel&&!settings)?(key_events[5]?6'b100000:6'd0):key_events[5:0]),
 .zoom_back(zoom_back),.zoom_mode(zoom_mode),.page(page),.instrument(instrument),.detail(detail),.clip(clip),.focus(focus),.paused(paused),.brightness(brightness),.contrast(contrast),.settings(settings),.param_select(param_select),.start(start),.cancel(cancel),.auto_mode(auto_mode),.tour_intro(tour_intro),.ensemble_mode(ensemble_mode),.ensemble_cancel(ensemble_cancel));
wire mix_live;wire[2:0] mix_field,mix_track,mix_solo;wire[24:0] mix_volumes;wire[4:0] mix_mute;
assign mix_panel=1'b0;assign mix_live=1'b0;assign mix_field=0;assign mix_track=0;assign mix_solo=7;assign mix_volumes={5{5'd8}};assign mix_mute=0;

wire[10:0] zoom_x,zoom_y;wire[2:0] zoom_level;wire[1:0] zoom_field;
tj_zoom_control zoom_control(.clk(ext_mem_clk),.rst(rst_all),.enable(zoom_mode),.instrument(instrument),.keys(key_events[5:0]),.held(key_held[5:0]),.ms_tick(key_ms_tick),.back(zoom_back),.field(zoom_field),.level(zoom_level),.x(zoom_x),.y(zoom_y));
always @(posedge ext_mem_clk or posedge rst_all)begin
 if(rst_all)begin has_frame<=0;loading_ui<=0;shown_page<=0;shown_instrument<=0;shown_detail<=0;shown_clip<=0;ack_previous<=0;buffer_ui[0]<=0;buffer_ui[1]<=0;buffer_ui[2]<=0;buffer_ui[3]<=0;buffer_ui[4]<=0;ram_retry<=0;end
 else begin
 ram_retry<=bist_failed&&key_events[0];
 ack_previous<=video_ack;
 if(ensemble_mode||zoom_mode)has_frame<=0;
 if(start)loading_ui<={page,instrument,clip,detail};
 if(start&&!auto_mode&&(frame_index>=8||shown_page==3))has_frame<=0;
 if(frame_ready)begin has_frame<=1;buffer_ui[frame_index]<=auto_mode?{page,instrument,clip,detail}:loading_ui;end
 // While the magnifier owns SDRAM, prepare the return identity in advance.
 // Never let special-raster ACKs select stale ordinary homepage metadata.
 if(zoom_mode||(!has_frame&&!ensemble_mode))begin
  shown_page<=zoom_mode?2'd1:page;shown_instrument<=instrument;
  shown_clip<=clip;shown_detail<=detail;
 end
 if(video_ack&&!ack_previous&&has_frame&&!special_video)
  {shown_page,shown_instrument,shown_clip,shown_detail}<=buffer_ui[frame_used];
 end
end
wire wr_valid,wr_ready,normal_wr_valid,ens_wr_valid;wire[20:0] wr_addr,normal_wr_addr,ens_wr_addr;wire[31:0] wr_data,normal_wr_data,ens_wr_data;
wire stream_wr_valid,zoom_wr_valid;wire[20:0] stream_wr_addr,zoom_wr_addr;wire[31:0] stream_wr_data,zoom_wr_data;
assign wr_valid=zoom_mode?zoom_wr_valid:ensemble_mode?ens_wr_valid:normal_wr_valid;
assign wr_addr=zoom_mode?zoom_wr_addr:ensemble_mode?ens_wr_addr:normal_wr_addr;
assign wr_data=zoom_mode?zoom_wr_data:ensemble_mode?ens_wr_data:normal_wr_data;
// R31: R25 full preload; no SD stream runs while the ensemble plays.
assign stream_fault=0;assign stream_warm=1;assign stream_produced=0;assign stream_file_req=0;assign stream_file_sector=0;assign stream_file_wa=0;assign stream_wr_valid=0;assign stream_wr_addr=0;assign stream_wr_data=0;

tj_zoom_loader zoom_loader(.clk(ext_mem_clk),.rst(rst_all),.enable(zoom_mode),.instrument(instrument),.req(zoom_file_req),.sector(zoom_file_sector),.ready(file_ready&&file_owner==3&&file_available),.wa(zoom_file_wa),.wd(file_word),.wr_valid(zoom_wr_valid),.wr_ready(wr_ready&&zoom_mode),.wr_addr(zoom_wr_addr),.wr_data(zoom_wr_data),.loaded(zoom_loaded),.error(zoom_error),.progress(zoom_progress));
tj_ensemble_loader ensemble_loader(.clk(ext_mem_clk),.rst(rst_all),.start(start&&ensemble_mode),.cancel(!ensemble_mode||ensemble_cancel),
 .req(ens_file_req),.sector(ens_file_sector),.ready(file_ready&&file_owner==1&&file_available),.wa(ens_file_wa),.wd(file_word),.busy(ens_busy),.loaded(ens_loaded),.error(ens_error),.progress(ens_progress),
 .wr_valid(ens_wr_valid),.wr_ready(wr_ready&&ensemble_mode),.wr_addr(ens_wr_addr),.wr_data(ens_wr_data));
tj_media loader(.clk(ext_mem_clk),.rst(rst_all),.mounted(mounted),.fs_error(fs_error),
 .req(normal_file_req),.sector(normal_file_sector),.ready(file_ready&&file_owner==0&&file_available),.wa(normal_file_wa),.wd(file_word),
 .start(start&&!ensemble_mode&&!zoom_mode),.cancel(cancel),.carousel(auto_mode),.external_overwrite(ensemble_mode||zoom_mode),.page(page),.instrument(instrument),.clip(clip),.detail(detail),
 .busy(media_busy),.done(media_done),.frame_ready(frame_ready),.error(media_error),.frame_index(frame_index),.audio_base(normal_audio_base),.preload_progress(preload_progress),.audio_loaded(normal_audio_loaded),.audio_samples(normal_audio_samples),
 .wr_valid(normal_wr_valid),.wr_ready(wr_ready&&!ensemble_mode),.wr_addr(normal_wr_addr),.wr_data(normal_wr_data));

wire Sdr_init_done,Sdr_init_ref_vld,Sdr_busy,App_rd_en,Sdr_rd_en,App_wr_en;
wire[6:0] App_rd_count;
wire bist_done,bist_we,bist_re;wire[3:0] bist_stage;
wire[20:0] bist_address;wire[31:0] bist_data,bist_expected,bist_actual;
wire[20:0] App_rd_addr,App_wr_addr;wire[31:0] Sdr_rd_dout,App_wr_din;
wire video_req,video_clear,video_we,video_re;wire[31:0] video_word,video_wdata;wire[9:0] video_used;
wire audio_enable=audio_loaded&&!navigation_busy&&!start&&!zoom_mode&&(page==1||page==3);
wire normal_video_clear,normal_video_we,normal_video_ack;wire[31:0] normal_video_wdata;
wire ens_video_clear,ens_video_we,ens_video_ack;wire[31:0] ens_video_wdata;
wire ens_mem_req,ens_mem_accept,ens_mem_valid,ens_fault;wire[20:0] ens_mem_addr;wire[6:0] ens_mem_count;wire[31:0] ens_mem_data;wire[2:0] ens_stage;wire[6:0] ens_step;
assign special_video=ensemble_mode||zoom_mode;
assign video_ack=special_video?ens_video_ack:normal_video_ack;assign video_clear=special_video?ens_video_clear:normal_video_clear;
assign video_we=special_video?ens_video_we:normal_video_we;assign video_wdata=special_video?ens_video_wdata:normal_video_wdata;
tj_ensemble_raster #(.VIDEO_HIGH(440),.HD_ROWS(1080)) ensemble_video(.clk(ext_mem_clk),.rst(rst_all),.enable(special_video),.loaded(zoom_mode?zoom_loaded:(ens_loaded&&!ens_busy)),.position(position_mem),.zoom_mode(zoom_mode),.zoom_x(zoom_x),.zoom_y(zoom_y),.zoom_level(zoom_level),
 .read_req(video_req),.read_ack(ens_video_ack),.video_clear(ens_video_clear),.video_we(ens_video_we),.video_data(ens_video_wdata),.video_used(video_used),
 .mem_req(ens_mem_req),.mem_addr(ens_mem_addr),.mem_count(ens_mem_count),.mem_accept(ens_mem_accept),.mem_valid(ens_mem_valid),.mem_data(ens_mem_data),.stage(ens_stage),.anim_step(ens_step),.fault(ens_fault));
assign video_used[9]=1'b0;
wire audio_clear,audio_we,audio_re,audio_empty,audio_fifo_valid;wire[31:0] audio_wdata,audio_fifo_data;wire[9:0] audio_used;wire memory_fault;
tj_memory #(.VIDEO_LOW(384),.VIDEO_HIGH(448),.HD_ROWS(1080)) memory(.clk(ext_mem_clk),.rst(rst_all|ram_retry),.init_done(Sdr_init_done&&bist_done&&!bist_failed),.refresh(Sdr_init_ref_vld),.busy(Sdr_busy),
 .video_suspend((auto_mode&&media_busy)||special_video),.read_req(video_req&&!special_video),.read_ack(normal_video_ack),.frame_index(frame_index),.frame_used(frame_used),.video_clear(normal_video_clear),.video_we(normal_video_we),.video_data(normal_video_wdata),.video_used(video_used),
 .stream_mode(1'b0),.stream_produced(stream_produced),.stream_consumed(stream_consumed),.audio_enable(audio_enable),.packed_pcm(auto_mode||ensemble_mode),.audio_base(audio_base),.audio_length(audio_samples),.audio_clear(audio_clear),.audio_we(audio_we),.audio_data(audio_wdata),.audio_used(audio_used),
 .wr_valid(wr_valid),.wr_ready(wr_ready),.wr_addr(wr_addr),.wr_data(wr_data),
 .app_we(App_wr_en),.app_wa(App_wr_addr),.app_wd(App_wr_din),.app_re(App_rd_en),.app_ra(App_rd_addr),.app_count(App_rd_count),.rd_valid(Sdr_rd_en),.rd_data(Sdr_rd_dout),.fault(memory_fault),.ens_request(ens_mem_req&&special_video),.ens_address(ens_mem_addr),.ens_count(ens_mem_count),.ens_accept(ens_mem_accept),.ens_valid(ens_mem_valid),.ens_data(ens_mem_data));
tj_ram_bist ram_test(.clk(ext_mem_clk),.rst(rst_all|ram_retry),.init_done(Sdr_init_done),.busy(Sdr_busy),.refresh(Sdr_init_ref_vld),
 .done(bist_done),.failed(bist_failed),.stage(bist_stage),.wr_en(bist_we),.rd_en(bist_re),.address(bist_address),.data(bist_data),
 .rd_valid(Sdr_rd_en),.rd_data(Sdr_rd_dout),.expected(bist_expected),.actual(bist_actual));
wire sdr_ras,sdr_cas,sdr_we;wire[10:0] sdr_addr;wire[1:0] sdr_ba;wire[3:0] sdr_dm;wire[31:0] sdr_dq;
tj_sdram U3(.Clk(ext_mem_clk),.Clk_sft(ext_mem_clk_sft),.Rst(rst_all|ram_retry),.Sdr_init_done(Sdr_init_done),.Sdr_init_ref_vld(Sdr_init_ref_vld),.Sdr_busy(Sdr_busy),
 .App_wr_en(bist_done?App_wr_en:bist_we),.App_wr_addr(bist_done?App_wr_addr:bist_address),.App_wr_dm(4'd0),.App_wr_din(bist_done?App_wr_din:bist_data),
 .App_rd_en(bist_done?App_rd_en:bist_re),.App_rd_addr(bist_done?App_rd_addr:bist_address),.App_rd_count(bist_done?App_rd_count:7'd64),
 .Sdr_rd_en(Sdr_rd_en),.Sdr_rd_dout(Sdr_rd_dout),.ras_n(sdr_ras),.cas_n(sdr_cas),.we_n(sdr_we),.addr(sdr_addr),.ba(sdr_ba),.dm(sdr_dm),.dq(sdr_dq));
EG_PHY_SDRAM_2M_32 physical_ram(.clk(ext_mem_clk_sft),.ras_n(sdr_ras),.cas_n(sdr_cas),.we_n(sdr_we),.addr(sdr_addr),.ba(sdr_ba),.dq(sdr_dq),.cs_n(1'b0),.dm0(sdr_dm[0]),.dm1(sdr_dm[1]),.dm2(sdr_dm[2]),.dm3(sdr_dm[3]),.cke(1'b1));
rfifo_32_32_512 #(.ADDR_WIDTH_W(9),.ADDR_WIDTH_R(9),.AL_FULL_NUM(509)) video_fifo(.clkw(ext_mem_clk),.clkr(ui_clk),.rst(rst_all|video_clear),.we(video_we),.di(video_wdata),.re(video_re),.dout(video_word),.wrusedw(video_used[8:0]),.rdusedw(),.valid(),.full_flag(),.empty_flag(),.afull(),.aempty());
tj_async_fifo audio_fifo(.wclk(ext_mem_clk),.rclk(ui_clk),.rst(audio_clear),.we(audio_we),.din(audio_wdata),.re(audio_re),.dout(audio_fifo_data),.valid(audio_fifo_valid),.empty(audio_empty),.full(),.used(audio_used));
wire hs0,vs0,de0,hs1,vs1,de1;wire[23:0] photo;
video_timing_data timing(.video_clk(video_clk),.rst(rst_all),.read_req(video_req),.read_req_ack(video_ack),.hs(hs0),.vs(vs0),.de(de0));
video_delay delay_video(.video_clk(ui_clk),.rst(rst_all),.read_en(video_re),.read_data(video_word[31:8]),.hs(hs0),.vs(vs0),.de(de0),.hs_r(hs1),.vs_r(vs1),.de_r(de1),.vout_data(photo));

// Multi-bit mailbox is stable between user actions; capture only at frame boundary.
wire[27:0] ui_mailbox={ensemble_mode,ens_stage,tour_intro,param_select,settings,auto_mode,contrast,brightness,focus,shown_detail,shown_clip,shown_instrument,shown_page,instrument};
reg[27:0] ui_sync1,ui_sync2,ui_frame;reg vs_previous,ui_pending;
always @(posedge ui_clk or posedge rst_all)begin
 if(rst_all)begin ui_sync1<=0;ui_sync2<=0;ui_frame<=0;vs_previous<=0;ui_pending<=1;end
 else begin
  ui_sync1<=ui_mailbox;ui_sync2<=ui_sync1;vs_previous<=vs1;
  if(!vs1&&vs_previous)ui_pending<=1;
  if(ui_pending&&!de1)ui_frame<=ui_sync2;
  if(de1)ui_pending<=0;
 end
end
wire audio_valid,normal_audio_valid;wire[23:0] audio_left_data,normal_audio_data;wire[21:0] normal_audio_position,ensemble_position;wire normal_playing,normal_underrun;wire[23:0] audio_right_data=audio_left_data;
wire playing,audio_underrun;
reg[1:0] finished_sync;
always @(posedge ext_mem_clk or posedge rst_all)if(rst_all)finished_sync<=0;
else finished_sync<={finished_sync[0],audio_loaded&&(position_mem>=audio_samples)};
assign audio_finished=finished_sync[1];
tj_audio sound(.audio_clk(audio_mclk),.pixel_clk(ui_clk),.rst(rst_all),.enable(audio_enable),.paused(paused||tour_intro),.short_clip(auto_mode),.packed_pcm(auto_mode||ensemble_mode),.length(audio_samples),
 .fifo_empty(audio_empty),.fifo_valid(audio_fifo_valid),.fifo_data(audio_fifo_data),.fifo_re(normal_audio_re),
 .sample_valid(normal_audio_valid),.sample_data(normal_audio_data),.position(normal_audio_position),.playing(normal_playing),.underrun(normal_underrun));
wire ensemble_audio_re,ensemble_audio_valid,ensemble_playing,ensemble_underrun;wire signed[15:0] ensemble_pcm;wire[15:0] stem_pcm;wire[2:0] stem_pcm_track;wire stem_pcm_valid;
// R31: one packed mixed PCM player, identical tj_audio RTL to R25.
assign stem_pcm=0;assign stem_pcm_track=0;assign stem_pcm_valid=0;
assign audio_re=normal_audio_re;
assign audio_valid=normal_audio_valid;
assign audio_left_data=normal_audio_data;
assign audio_position=normal_audio_position;
assign playing=normal_playing;
assign audio_underrun=normal_underrun;
// Gray counter CDC:sample progress cannot tear around binary carries.
reg[21:0] position_gray;(* async_reg="true" *)reg[21:0] position_g1,position_g2;
always @(posedge ui_clk or posedge rst_all)if(rst_all)position_gray<=0;else position_gray<=(audio_position>>1)^audio_position;
always @(posedge ext_mem_clk or posedge rst_all)if(rst_all)begin position_g1<=0;position_g2<=0;end else begin position_g1<=position_gray;position_g2<=position_g1;end
function[21:0] from_gray;input[21:0] g;integer b;begin from_gray[21]=g[21];for(b=20;b>=0;b=b-1)from_gray[b]=from_gray[b+1]^g[b];end endfunction
reg[21:0] position_binary;
always @(posedge ext_mem_clk or posedge rst_all)if(rst_all)position_binary<=0;else position_binary<=from_gray(position_g2);
assign position_mem=position_binary;

wire hs,vs,de;wire[23:0] vout_data;wire[7:0] hd_glyph;wire[3:0] hd_x,hd_y;wire hd_text;
wire hd_photo;wire[3:0] hd_frac_y,hd_footer_mode;wire[9:0] hd_px,hd_py;
wire native_de,native_hs,native_vs;wire[23:0] native_rgb;
wire preview_de,preview_hs,preview_vs;wire[23:0] preview_photo;
tj_loading_preview loading_preview(.clk(ui_clk),.rst(rst_all),.de(de1),.hs(hs1),.vs(vs1),.photo(photo),
 .capture_home(has_frame&&shown_page==0&&!auto_mode&&!media_busy),.loading(auto_mode&&media_busy&&preload_progress<20),.has_frame(has_frame||(ensemble_mode&&ens_loaded&&!ens_busy)||(zoom_mode&&zoom_loaded)),
 .ode(preview_de),.ohs(preview_hs),.ovs(preview_vs),.out_photo(preview_photo));
tj_ui #(.WIDE(2),.NATIVE_TEXT(1)) display(.clk(ui_clk),.rst(rst_all),.de(preview_de),.hs(preview_hs),.vs(preview_vs),.photo(preview_photo),
 .page(ui_frame[27]?2'd3:ui_frame[3:2]),.instrument((ui_frame[23]||ui_frame[3:2]==0)?ui_frame[1:0]:ui_frame[5:4]),.clip(ui_frame[6]),.detail(ui_frame[8:7]),.focus(ui_frame[11:9]),
 .zoom(zoom_mode),.zoom_x(zoom_x),.zoom_y(zoom_y),.zoom_level(zoom_level),.zoom_field(zoom_field),
 .mix_panel(mix_panel),.mix_field(mix_field),.mix_track(mix_track),.mix_volumes(mix_volumes),.mix_mute(mix_mute),.mix_solo(mix_solo),.mix_live(mix_live),.stem_pcm(stem_pcm),.stem_pcm_track(stem_pcm_track),.stem_valid(stem_pcm_valid),
 .ensemble(ui_frame[27]),.ensemble_stage(ui_frame[26:24]),.tour_intro(ui_frame[23]),.carousel(ui_frame[20]),.settings(ui_frame[21]),.param_select(ui_frame[22]),.recovering(display_busy&&!has_frame&&!special_video&&!auto_mode),.preload_progress(zoom_mode?zoom_progress:ensemble_mode?ens_progress:preload_progress),.brightness(ui_frame[15:12]),.contrast(ui_frame[19:16]),.busy(display_busy),.error(zoom_mode?zoom_error:ensemble_mode?ens_error:media_error),.playing(playing),
 .test_done(bist_done),.test_failed(bist_failed),.test_stage(bist_stage),.test_expected(bist_expected),.test_actual(bist_actual),
 .progress(audio_position),.total(audio_samples),.pcm(audio_left_data[23:8]),.pcm_valid(audio_valid),.ode(de),.ohs(hs),.ovs(vs),.rgb(vout_data),.hd_glyph(hd_glyph),.hd_x(hd_x),.hd_y(hd_y),.hd_text(hd_text),.hd_photo(hd_photo),.hd_frac_y(hd_frac_y),.hd_footer_mode(hd_footer_mode),.hd_px(hd_px),.hd_py(hd_py));

tj_native_text native_text(.clk(video_clk),.rst(rst_all),.de(de),.hs(hs),.vs(vs),.rgb(vout_data),.glyph(hd_glyph),.gx(hd_x),.gy(hd_y),.text_on(hd_text),.photo_on(hd_photo),.frac_y(hd_frac_y),.footer_mode(hd_footer_mode),.px(hd_px),.py(hd_py),.ode(native_de),.ohs(native_hs),.ovs(native_vs),.out_rgb(native_rgb));
assign status_led={bist_failed|memory_fault|audio_underrun|stream_fault|ens_fault|(|media_error),media_busy,mounted,card_ready};
//25MHz source strobe becomes exactly one75MHz HDMI audio strobe.
reg[2:0] audio_valid_hd_sync;reg audio_valid_hd_old;
always @(posedge video_clk or posedge rst_all)begin
 if(rst_all)begin audio_valid_hd_sync<=0;audio_valid_hd_old<=0;end
 else begin audio_valid_hd_sync<={audio_valid_hd_sync[1:0],audio_valid};audio_valid_hd_old<=audio_valid_hd_sync[2];end
end
wire audio_hd_valid=audio_valid_hd_sync[2]&&!audio_valid_hd_old;
wire acr_valid;wire[19:0] acr_cts,acr_n;
wire axis_s_user,axis_s_valid,axis_s_last,axis_s_ready;wire[23:0] axis_s_data;
wire[9:0] tmds_ch0_data,tmds_ch1_data,tmds_ch2_data,tmds_clk_data;
audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_audio_valid (audio_hd_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 #(.ACTIVE(1920)) u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_vs          (native_vs),
    .I_de          (native_de),
    .I_rgb         (native_rgb),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 2200       ),
    .HSA                    ( 44         ),
    .HFP                    ( 88         ),
    .HBP                    ( 148        ),
    .HACTIVE                ( 1920       ),
    .VTOTAL                 ( 1125       ),
    .VSA                    ( 5          ),
    .VFP                    ( 4          ),
    .VBP                    ( 36         ),
    .VACTIVE                ( 1080       ),
    .VIDEO_VIC              ( 34         ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_all),
    .I_edid_read_trig   (1'b0),
    .O_edid_read_valid  (),
    .O_edid_read_data   (),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_hd_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (),
    .IO_ddc_sda         (),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_all),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
