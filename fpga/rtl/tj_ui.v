// All text and UI is generated in logic. Four aligned text/photo stages; glyph address is registered for timing.
module tj_ui #(parameter WIDE=0,NATIVE_TEXT=0)(input clk,rst,input de,hs,vs,input[23:0] photo,
 input[1:0] page,instrument,input clip,input[1:0] detail,input[2:0] focus,
 input zoom,input[10:0] zoom_x,zoom_y,input[2:0] zoom_level,input[1:0] zoom_field,
 input mix_panel,input[2:0] mix_field,mix_track,input[24:0] mix_volumes,input[4:0] mix_mute,input[2:0] mix_solo,input mix_live,
 input[15:0] stem_pcm,input[2:0] stem_pcm_track,input stem_valid,
 input ensemble,input[2:0] ensemble_stage,input tour_intro,carousel,settings,param_select,input[4:0] preload_progress,
 input recovering,input busy,input[7:0] error,input playing,input[3:0] brightness,contrast,
 input test_done,test_failed,input[3:0] test_stage,input[31:0] test_expected,test_actual,
 input[21:0] progress,total,input signed[15:0] pcm,input pcm_valid,
 output reg ode,ohs,ovs,output reg[23:0] rgb,
 output reg[7:0] hd_glyph,output reg[3:0] hd_x,hd_y,output reg hd_text,output reg hd_photo,output reg[3:0] hd_frac_y,hd_footer_mode,output reg[9:0] hd_px,hd_py);
reg[9:0] x,y;reg[1:0] native_subx;reg[3:0] native_suby;reg deold,vsold;reg[7:0] frame;
wire zoom_on=zoom===1'b1;wire mixpanel_on=(mix_panel===1'b1)&&!(settings===1'b1);
wire[4:0] selected_volume=mix_volumes>>(mix_track*5);
wire ensemble_on=(ensemble===1'b1);
wire intro_card=(tour_intro===1'b1);
wire return_loading=recovering===1'b1;
wire loading=return_loading||(carousel&&busy&&preload_progress<20)||(ensemble_on&&busy)||(zoom_on&&busy);
reg[1:0] previous_page,previous_inst,previous_detail;reg previous_clip;
`include "@PROJECT_ROOT@/rtl/tj_glyphs.vh"
`include "@PROJECT_ROOT@/rtl/tj_layout.vh"
reg[21:0] text_spans[0:255];reg[7:0] text_data[0:2047];
initial $readmemh("@PROJECT_ROOT@/rtl/tj_text_spans.hex",text_spans);
initial $readmemh("@PROJECT_ROOT@/rtl/tj_text_packed.hex",text_data);
reg[21:0] text_span1;reg[4:0] text_col1;reg[7:0] text_word;
reg text_space2,dict_override_valid;reg[7:0] glyph_override;
wire[10:0] text_byte_address=text_span1[10:0]+text_col1-text_span1[15:11];
wire[7:0] glyph=dict_override_valid?glyph_override:(text_space2?8'd0:text_word);
reg[7:0] lines[0:2047];reg[15:0] font[0:4095];
initial begin

 if(!NATIVE_TEXT&&WIDE==2)$readmemh("@PROJECT_ROOT@/rtl/tj_font_wide.hex",font);
 else if(!NATIVE_TEXT)$readmemh("@PROJECT_ROOT@/rtl/tj_font.hex",font);
 $readmemh("@PROJECT_ROOT@/rtl/tj_lines.hex",lines);
end
reg[12:0] textaddr_pipe;reg[9:0] xa,ya,txa,tya;
reg[7:0] lineid,glyph4;reg[3:0] glyph_y4;reg[15:0] bits;
reg[9:0] x1,y1,x2,y2,x3,y3,x4,y4;reg[23:0] bg1,bg2,bg3,bg4;reg[2:0] sync1,sync2,sync3,sync4;
`include "@PROJECT_ROOT@/rtl/tj_footer_layout.vh"
wire[3:0] footer_mode=zoom_on?8:mixpanel_on?5:ensemble_on&&!settings?7:loading?6:settings?5:page==0?0:page==1?1:page==2?2:carousel?4:3;
wire footer_on=x>=16&&x<616&&y>=458&&y<470;
reg footer_on1,footer_on2,footer_on3,footer_on4;
reg[3:0] fy1,fy2,fy3,fy4,fm1,fm2,fm3,fm4;
reg ph1,ph2,ph3,ph4;
wire final_photo;
always @(posedge clk)begin
 footer_on1<=footer_on;footer_on2<=footer_on1;footer_on3<=footer_on2;footer_on4<=footer_on3;
 fy1<=native_suby;fy2<=fy1;fy3<=fy2;fy4<=fy3;
 fm1<=footer_mode;fm2<=fm1;fm3<=fm2;fm4<=fm3;
 ph1<=final_photo;ph2<=ph1;ph3<=ph2;ph4<=ph3;
end
reg[9:0] scroll;reg[9:0] tx1,tx2,tx3,tx4;
wire[10:0] roll={1'b0,x}-16+scroll;
wire ticker=!ensemble_on&&!intro_card&&page==3&&y>=432&&y<448&&x>=16&&x<560;
wire[9:0] text_x=ticker?(16+((roll>=544)?roll-544:roll)):x;
reg[5:0] ensemble_seconds;reg[21:0] ensemble_next_second;
reg[5:0] seconds_frame;reg[3:0] sec_one,sec_ten,min_one,min_ten;
wire[15:0] wave_range_raw;reg[15:0] wave_range;always @(posedge clk)wave_range<=wave_range_raw;
wire wave_ready;
// Thin chronological editor-style waveform. Intro combines adjacent
// bins so both layouts retain the same2.048s time window and all extrema.
wire[7:0] wave_addr=(page==3)?((x-64)>>1):((x-48)&10'h3fe);
wire[7:0] wave_negative=(wave_range[7:0]<128)?(128-wave_range[7:0]):0;
wire[7:0] wave_positive=(wave_range[15:8]>128)?(wave_range[15:8]-128):0;
// Exact constant shift/add products, not two variable DSP multipliers.
function[13:0] wave_scale;input[7:0] v;reg[13:0] q;begin
 q={6'd0,v};
 wave_scale=ensemble_on?((q<<4)+(q<<2)):
            (page==3)?((q<<5)+(q<<3)+(q<<2)):((q<<5)-(q<<2));
end endfunction
wire[13:0] wave_neg_scaled=wave_scale(wave_negative);
wire[13:0] wave_pos_scaled=wave_scale(wave_positive);
wire[5:0] wave_limit=ensemble_on?10:(page==3)?22:14;
wire[5:0] wave_down=(wave_neg_scaled[13:7]>wave_limit)?wave_limit:wave_neg_scaled[12:7];
wire[5:0] wave_up=(wave_pos_scaled[13:7]>wave_limit)?wave_limit:wave_pos_scaled[12:7];
wire track_reset=(progress==0)||(instrument!=previous_inst)||(clip!=previous_clip);
tj_waveform waveform(.clk(clk),.rst(rst),.frame_tick(vs&&!vsold),.track_reset(track_reset),.playing(playing),.pcm(pcm),.pcm_valid(pcm_valid),.address(wave_addr),.pair_view(page==1),.range_out(wave_range_raw),.ready(wave_ready));
integer hex_digit;
function[7:0] hexglyph;input[3:0] n;begin
 if(n<10)hexglyph=GLYPH_ZERO+n;
 else case(n)10:hexglyph=G_A;11:hexglyph=G_B;12:hexglyph=G_C;13:hexglyph=G_D;14:hexglyph=G_E;default:hexglyph=G_F;endcase
end endfunction

// Independent source envelopes use the R25 ROM; total waveform consumes real PCM.
reg[3:0] stem_magnitude;
reg[3:0] stems[0:4095];
initial $readmemh("@PROJECT_ROOT@/rtl/tj_stems.hex",stems);
reg[8:0] stem_bin;reg[21:0] stem_progress;always @(posedge clk)stem_progress<=progress;
integer stem_history_index;reg[11:0] stem_address;

// Exact restoring division during vertical blanking; no combinational /6000.
reg[21:0] stem_dividend;reg[21:0] stem_quotient;
reg[12:0] stem_remainder;reg[4:0] stem_count;
wire[13:0] stem_trial={stem_remainder,stem_dividend[21]};
wire stem_take=stem_trial>=14'd6000;
wire[21:0] stem_result={stem_quotient[20:0],stem_take};
reg stem_settled;reg[2:0] stem_stage_frame;
wire stem_card_visible=stem_settled&&(stem_stage_frame==ensemble_stage);
function[21:0] stem_cue;input[2:0] k;begin case(k)1:stem_cue=426667;2:stem_cue=853333;3:stem_cue=1280000;4:stem_cue=1702841;default:stem_cue=0;endcase end endfunction
reg stem_band2,stem_line2,stem_name1;reg[2:0] stem_track2,stem_track1;reg stem_half1;
reg[9:0] stem_left2;reg[8:0] stem_top2;integer stem_i;reg[5:0] stem_column;reg[7:0] stem_offset;


reg stem_band3,stem_line3,stem_silent3;reg[8:0] stem_center3;reg[9:0] stem_left3;
always @*begin
 stem_band2=0;stem_line2=0;stem_name1=0;stem_track2=0;stem_track1=0;stem_half1=0;stem_left2=0;stem_top2=0;stem_column=0;stem_offset=0;stem_history_index=-1;stem_address=4095;
 for(stem_i=0;stem_i<5;stem_i=stem_i+1)if(ensemble_on&&stem_card_visible&&stem_i<=ensemble_stage)begin
  // Names occupy two16px cells; waves use48 thin columns to their right.
  if(y3>=(stem_i<2?208:stem_i<4?384:304)&&y3<(stem_i<2?224:stem_i<4?400:320)&&x3>=(stem_i==0||stem_i==2?16:stem_i==1||stem_i==3?432:224)&&x3<(stem_i==0||stem_i==2?208:stem_i==1||stem_i==3?624:416))begin
   stem_band2=1;stem_track2=stem_i;stem_left2=(stem_i==0||stem_i==2?16:stem_i==1||stem_i==3?432:224);stem_top2=(stem_i<2?208:stem_i<4?384:304);
  end
  if(ya[8:4]==(stem_i<2?13:stem_i<4?24:19)&&xa[9:4]>=(stem_i==0||stem_i==2?1:stem_i==1||stem_i==3?27:14)&&xa[9:4]<(stem_i==0||stem_i==2?3:stem_i==1||stem_i==3?29:16))begin stem_name1=1;stem_track1=stem_i;stem_half1=(stem_i==4)?xa[4]:!xa[4];end
 end
 // Entry animation keeps only the total waveform; independent strips
 // appear under their portraits after the frame-latched settling point.
 if(stem_band2&&x3>=stem_left2+40&&x3<stem_left2+184)begin
  stem_offset=x3-stem_left2-10'd40;
  stem_column=stem_offset/8'd3;
  stem_line2=(stem_offset%8'd3==0);
  stem_history_index={1'b0,stem_bin}-47+stem_column;
  if(stem_history_index>=0&&stem_history_index<440)stem_address={stem_track2,9'b0}+stem_history_index;

 end
end
always @(posedge clk)begin
 stem_magnitude<=stems[stem_address];stem_band3<=stem_band2;stem_line3<=stem_line2;stem_center3<=stem_top2+8;stem_left3<=stem_left2;
 stem_silent3<=mix_live&&(mix_mute[stem_track2]||(mix_solo<5&&mix_solo!=stem_track2));
 if(rst)begin stem_bin<=0;stem_settled<=0;stem_stage_frame<=0;end
 else if(vs&&!vsold)begin stem_settled<=progress>=stem_cue(ensemble_stage)+105600;stem_stage_frame<=ensemble_stage;end
 else if(stem_count==1)stem_bin<=stem_result[8:0];
end
always @(posedge clk)begin
 if(rst)begin stem_dividend<=0;stem_quotient<=0;stem_remainder<=0;stem_count<=0;end
 else if(vs&&!vsold)begin stem_dividend<=stem_progress;stem_quotient<=0;stem_remainder<=0;stem_count<=22;end
 else if(stem_count!=0)begin
  stem_dividend<={stem_dividend[20:0],1'b0};stem_quotient<=stem_result;
  stem_remainder<=stem_take?stem_trial-14'd6000:stem_trial;
  stem_count<=stem_count-1'b1;
 end
end
wire[2:0] stem_height=(stem_magnitude==0)?0:(stem_magnitude>=13)?6:(stem_magnitude>=10)?5:(stem_magnitude>=8)?4:(stem_magnitude>=5)?3:(stem_magnitude>=3)?2:1;

function[10:0] roi_width;input[2:0] z;begin case(z)0:roi_width=336;1:roi_width=252;2:roi_width=168;3:roi_width=126;default:roi_width=84;endcase end endfunction
function[9:0] roi_height;input[2:0] z;begin case(z)0:roi_height=288;1:roi_height=216;2:roi_height=144;3:roi_height=108;default:roi_height=72;endcase end endfunction
// Overview coordinates use a small time-shared exact divider in blanking.
reg[10:0] roi_x_snapshot,roi_y_snapshot;reg[2:0] roi_z_snapshot;
reg[1:0] roi_phase;reg roi_busy;
reg[8:0] roi_l,roi_t,roi_w,roi_h;
wire[10:0] roi_operand=(roi_phase==0)?roi_x_snapshot:(roi_phase==1)?roi_y_snapshot:(roi_phase==2)?roi_width(roi_z_snapshot):{1'b0,roi_height(roi_z_snapshot)};
wire[13:0] roi_numerator=({3'd0,roi_operand}<<3)-roi_operand;
reg[10:0] roi_dividend;reg[8:0] roi_quotient;reg[2:0] roi_remainder;reg[3:0] roi_count;
wire[3:0] roi_trial={roi_remainder,roi_dividend[10]};
wire[3:0] roi_difference=roi_trial-4'd5;
wire roi_bit=!roi_difference[3];
wire[8:0] roi_result={roi_quotient[7:0],roi_bit};
always @(posedge clk)begin
 if(rst)begin roi_phase<=0;roi_busy<=0;roi_x_snapshot<=472;roi_y_snapshot<=336;roi_z_snapshot<=0;roi_l<=82;roi_t<=58;roi_w<=58;roi_h<=50;roi_count<=0;roi_dividend<=0;roi_quotient<=0;roi_remainder<=0;end
 else if(vs&&!vsold)begin roi_x_snapshot<=zoom_x;roi_y_snapshot<=zoom_y;roi_z_snapshot<=zoom_level;roi_phase<=0;roi_busy<=1;roi_count<=0;end
 else if(roi_busy)begin
  if(roi_count==0)begin roi_dividend<=roi_numerator[13:3];roi_quotient<=0;roi_remainder<=0;roi_count<=11;end
  else begin
   roi_dividend<={roi_dividend[9:0],1'b0};roi_quotient<=roi_result;roi_remainder<=roi_bit?roi_difference[2:0]:roi_trial[2:0];roi_count<=roi_count-1'b1;
   if(roi_count==1)begin
    case(roi_phase)0:roi_l<=roi_result;1:roi_t<=roi_result;2:roi_w<=roi_result;3:roi_h<=roi_result;endcase
    roi_phase<=roi_phase+1'b1;if(roi_phase==3)roi_busy<=0;
   end
  end
 end
end
wire[9:0] roi_left=16+roi_l,roi_top=104+roi_t;
wire[9:0] roi_right=roi_left+roi_w,roi_bottom=roi_top+roi_h;
wire roi_border=zoom_on&&!loading&&error==0&&x>=roi_left&&x<=roi_right&&y>=roi_top&&y<=roi_bottom&&(x<roi_left+2||x>roi_right-2||y<roi_top+2||y>roi_bottom-2);
// Snapshot slow-changing coefficients once per frame. The offset really is
// ten bits: an unsized x-16 creates a32-bit multiplier and wastes fabric.
reg[21:0] bar_total;reg[31:0] bar_target;
wire[9:0] bar_offset=x-10'd16;
// Only x=16..623 uses this value. Advance the exact product by addition.
// x and this accumulator advance on the same edge; WIDE=1 holds both.
reg[31:0] bar_pixel_product;
always @(posedge clk)begin
 if(rst||!de||x==15)bar_pixel_product<=0;
 else if(WIDE!=1||native_subx==2)bar_pixel_product<=bar_pixel_product+bar_total;
end
wire bar_pixel_on=bar_pixel_product<bar_target;
always @(posedge clk)begin
 if(rst)begin bar_total<=0;bar_target<=0;end
 else if(vs&&!vsold)begin bar_total<=total;bar_target<=progress*32'd608;end
end
reg[5:0] fade;reg busy_old;
wire home_features=page==0&&focus>=4;
wire[5:0] base_textpage=(page==0)?(home_features?57:0):((page==1)?(1+{instrument,1'b0}+clip):((page==2)?(9+instrument*3+detail):(carousel?(21+instrument*4+detail):(38+instrument*2+clip))));
wire panel=settings&&x>=160&&x<480&&y>=128&&y<352;
wire[5:0] textpage=return_loading?61:panel?37:zoom_on&&!loading?58:mixpanel_on?59:loading?(zoom_on?60:ensemble_on?56:46):(panel?37:(ensemble_on?(51+ensemble_stage):(intro_card?(47+instrument):base_textpage)));
// R32 text-only layout transform. Physical video, photos and controls stay separate.
`include "@PROJECT_ROOT@/rtl/tj_spacing.vh"
reg[9:0] layout_y;reg layout_valid;reg signed[10:0] mapped_x;
reg[9:0] ty1,ty2,ty3;reg valid1,valid2,valid3,valid4;
wire compact_caption=!WIDE&&!ensemble_on&&!intro_card&&!loading&&!settings&&!zoom_on&&page==3&&y>=400&&y<448;
wire spacing_side=(textpage==0)?(x>=352):(textpage==57&&x>=320);
wire signed[10:0] horizontal_offset=WIDE?spacing_dx_hd(textpage,layout_y[8:4],spacing_side):spacing_dx(textpage,layout_y[8:4],spacing_side);
reg[9:0] layout_x;
wire[5:0] native_font_phase={layout_x[3:0],1'b0}+layout_x[3:0]+native_subx;
function[3:0] native_font_column;input[5:0] q;begin case(q)
0:native_font_column=0;
1:native_font_column=0;
2:native_font_column=0;
3:native_font_column=1;
4:native_font_column=1;
5:native_font_column=2;
6:native_font_column=2;
7:native_font_column=3;
8:native_font_column=3;
9:native_font_column=4;
10:native_font_column=4;
11:native_font_column=4;
12:native_font_column=5;
13:native_font_column=5;
14:native_font_column=6;
15:native_font_column=6;
16:native_font_column=7;
17:native_font_column=7;
18:native_font_column=8;
19:native_font_column=8;
20:native_font_column=8;
21:native_font_column=9;
22:native_font_column=9;
23:native_font_column=10;
24:native_font_column=10;
25:native_font_column=11;
26:native_font_column=11;
27:native_font_column=12;
28:native_font_column=12;
29:native_font_column=12;
30:native_font_column=13;
31:native_font_column=13;
32:native_font_column=14;
33:native_font_column=14;
34:native_font_column=15;
35:native_font_column=15;
default:native_font_column=0;endcase end endfunction

always @*begin
 layout_y=y;layout_valid=1;
 if(textpage>=1&&textpage<=20)begin
  if(y>=48&&y<56)layout_valid=0;
  if(y>=56&&y<72)layout_y=y-8;
  if(textpage<=8)begin
   if(y>=320&&y<328)layout_valid=0;
   if(y>=328&&y<344)layout_y=y-8;
  end
 end
 if(textpage==0&&(x<272||x>=352))begin
  if(y>=224&&y<230)layout_valid=0;
  if(y>=230&&y<246)layout_y=y-6;
 end
 if(textpage==37&&y>=160&&y<336)begin
  layout_valid=0;
  if(y>=184&&y<200)begin layout_y=y-8;layout_valid=1;end
  if(y>=272&&y<288)begin layout_y=y-32;layout_valid=1;end
 end
 if(textpage==58&&x<256&&y>=336&&y<416)begin
  layout_valid=0;
  if(y>=352&&y<368)begin layout_y=y-16;layout_valid=1;end
  if(y>=400&&y<416)begin layout_y=y-32;layout_valid=1;end
 end
 // Footer-adjacent captions only: same bitmap family,14px glyph in16px cell.
 // One extra source pixel per7 output pixels, no multiplier or divider.
 // R35: original 16x16 bitmap, no compact-caption resampling.
 mapped_x=$signed({1'b0,text_x})+horizontal_offset;
 if(textpage==0&&x>=272&&x<352)mapped_x=$signed({1'b0,text_x});
 if(textpage==0&&x>=352&&mapped_x<352)layout_valid=0;
 if(mapped_x<0||mapped_x>=640)layout_valid=0;
 layout_x=mapped_x[9:0];
 if(WIDE==1&&native_font_phase>=36)layout_valid=0;
 // R35: retain the full 16 columns; layout anchors are unchanged.
end
wire[10:0] lineaddr=textpage*30+layout_y[8:4];
reg[19:0] visible_progress;
wire[16:0] scene_progress=(visible_progress>=284400)?visible_progress-284400:((visible_progress>=189600)?visible_progress-189600:((visible_progress>=94800)?visible_progress-94800:visible_progress));
// R19 composes old/new photos in tj_memory, without altering their colors.
wire[4:0] photo_gain=5'd16;
function[23:0] ivory_panel;input[23:0] c;reg[9:0] a,b,d;begin
 a={2'b0,c[23:16]}+732;b={2'b0,c[15:8]}+723;d={2'b0,c[7:0]}+696;ivory_panel={a[9:2],b[9:2],d[9:2]};
end endfunction
wire[12:0] textaddr=lineid*40+tx1[9:4];
wire in_photo=zoom_on?1'b1:(page==3)?1'b1:(page==0)?!home_features&&((x>=40&&x<280)||(x>=360&&x<600))&&((y>=48&&y<228)||(y>=250&&y<430)):
              (x>=16&&x<((page==1)?336:416)&&y>=((page==1)?80:88)&&y<((page==1)?320:388));
wire card_region=(page==0)&&focus<4&&((instrument[0]==0)?(x>=34&&x<286):(x>=354&&x<606))&&((instrument[1]==0)?(y>=46&&y<248):(y>=248&&y<450));
wire card_inside=(instrument[0]==0)?(x>=38&&x<282):(x>=358&&x<602);
wire card_yinside=(instrument[1]==0)?(y>=50&&y<244):(y>=252&&y<446);
wire border=card_region&&!(card_inside&&card_yinside);
wire label=(page==0)&&!home_features&&((y>=228&&y<248)||(y>=430&&y<448));
// Five equal 112-pixel controls. Text starts are generated from these cells.
wire[9:0] option_left=button_left(focus);
wire option_border=!loading&&!zoom_on&&page==1&&y>=410&&y<438&&x>=option_left&&x<option_left+BUTTON_WIDTH&& (y<413||y>=435||x<option_left+3||x>=option_left+BUTTON_WIDTH-3);
wire[7:0] glow=frame[6]?8'd180+{2'b0,~frame[5:0]}:8'd180+{2'b0,frame[5:0]};
reg[23:0] composed;integer rr,gg,bb;
function[7:0] channel;input[7:0] v;reg signed[8:0] centered;reg signed[6:0] factor;reg signed[15:0] product,z;begin
 // Default4 is an exact passthrough; signed shift rounds negative values correctly.
 centered=$signed({1'b0,v})-9'sd128;
 factor=7'sd4+$signed({3'b0,contrast})*7'sd3;
 product=centered*factor;
 z=(product>>>4)+16'sd128+($signed({1'b0,brightness})-16'sd4)*16'sd24;
 if(z<0)channel=0;else if(z>255)channel=255;else channel=z;
end endfunction
assign final_photo=in_photo&&!label&&!border&&!option_border&&!panel&&!intro_card&&!loading&&!roi_border&&!mixpanel_on
 &&!(page==3&&(y>=397||(!ensemble_on&&x>=48&&x<592&&y>=340&&y<394)||(x>=512&&x<624&&y>=8&&y<40)||(carousel&&x>=144&&x<240&&y>=8&&y<40)))
 &&!(zoom_on&&(y<80||y>=384||x<16||x>=624||(x>=240&&x<288)||(x<288&&(y<104||y>=272))))
 &&!(page==1&&!zoom_on&&y>=366);
always @*begin
 rr=0;gg=0;bb=0;
 composed=24'hf4f1e8;
 if(y<48)composed=24'hf4f1e8;
 if(y==47||y==447)composed=24'hd6dbd1;
 if(page!=0&&page!=3&&x==343&&y>=88&&y<320)composed=24'hd6dbd1;
 if(y>=448)composed=24'he8eadd;
 if(in_photo)begin
  composed={channel(photo[23:16]),channel(photo[15:8]),channel(photo[7:0])};
  // Fade through warm ivory. Both sides of a carousel transition use real frame timing.
  if(photo_gain<16)begin
   rr=composed[23:16]*photo_gain+244*(16-photo_gain);
   gg=composed[15:8]*photo_gain+241*(16-photo_gain);
   bb=composed[7:0]*photo_gain+232*(16-photo_gain);
   composed={rr[11:4],gg[11:4],bb[11:4]};
  end
 end
 if(label)composed=24'he8eadd;
 if(border||option_border)composed={8'h35,1'b0,glow[7:1],8'h62};
 if(!zoom_on&&page==1&&x>=16&&x<336&&y>=366&&y<400)composed=24'he8eadd;
 if(!zoom_on&&page==1&&y>=443&&y<449&&x>=16&&x<624)composed=24'hd6dbd1;
 // Compare products to avoid a run-time divider.
 if(!zoom_on&&page==1&&total!=0&&y>=443&&y<449&&x>=16&&x<624&&bar_pixel_on)composed=24'h386b59;
 if(!zoom_on&&page==1&&x>=600&&x<616&&y>=52&&y<68)composed=playing?24'h386b59:24'hbd9757;
 if(home_features&&y>=144&&y<320&&((x>=48&&x<304)||(x>=336&&x<592)))begin
  composed=24'he8eadd;
  if(((focus==4&&x<304)||(focus==5&&x>=336))&&(x<51||x>=589||(x>=301&&x<339)||y<147||y>=317))composed=24'h386b59;
 end
 if(page==0&&carousel&&busy&&x>=352&&x<512&&y>=40&&y<44)composed=((x-352)<preload_progress*8)?24'h386b59:24'hd6dbd1;
 if(page==3&&(y>=400||(!ensemble_on&&x>=48&&x<592&&y>=340&&y<394)||(x>=512&&x<624&&y>=8&&y<40)))composed=ivory_panel(composed);
 if(page==3&&carousel&&x>=144&&x<240&&y>=8&&y<40)composed=24'he8eadd;
 if(page==3&&y==399)composed=24'hb89a65;

 if(page==3&&total!=0&&y>=397&&y<399&&x>=16&&x<624)composed=(bar_pixel_on)?24'h386b59:24'hd6dbd1;
 if(intro_card)begin
  composed=24'hf4f1e8;
  if(y==47||y==447)composed=24'hd6dbd1;
  if(x>=224&&x<416&&(y==176||y==284))composed=24'hb89a65;
 end
 if(zoom_on&&!loading)begin
  if(y<80||y>=384||x<16||x>=624||(x>=240&&x<288)||(x<288&&(y<104||y>=272)))composed=24'hf4f1e8;
  if((x==15||x==240)&&y>=103&&y<273)composed=24'hd6dbd1;
  if((y==103||y==272)&&x>=15&&x<=240)composed=24'hd6dbd1;
  if((x==287||x==624)&&y>=87&&y<377)composed=24'h386b59;
  if((y==87||y==376)&&x>=287&&x<=624)composed=24'h386b59;
  if(x>=12&&x<240&&y>=304&&y<336)composed=24'he0e8d9;
 end
 if(mixpanel_on)begin
  composed=24'hf4f1e8;
  if(x>=160&&x<480&&y>=112&&y<368)begin
   composed=24'he8eadd;
   if(x<163||x>=477||y<115||y>=365)composed=24'h386b59;
   if(y>=144+mix_field*48&&y<176+mix_field*48&&x>=168&&x<472)composed=24'hd9e4d5;
  end
 end
 if(panel)begin
  composed=ivory_panel(composed);
  if(x<163||x>=477||y<131||y>=349)composed=24'h386b59;
  if(x>=176&&x<464&&((!param_select&&y>=176&&y<232)||(param_select&&y>=264&&y<320)))composed=24'he0e8d9;
  if(x>=192&&x<448&&y>=214&&y<220)composed=(((x-192)*9)<((brightness+1)*256))?24'h386b59:24'hcbd4c5;
  if(x>=192&&x<448&&y>=302&&y<308)composed=(((x-192)*9)<((contrast+1)*256))?24'h386b59:24'hcbd4c5;
 end
 // Non-photographic preparation screen; all shapes remain crisp at VGA.
 if(loading)begin
  composed=24'hf4f1e8;
  if(y==47||y==447)composed=24'hd6dbd1;
  if(x>=128&&x<512&&y>=250&&y<262)composed=(((x-128)*((ensemble_on||zoom_on)?31:20))<preload_progress*384)?24'h386b59:24'he0e8d9;
  if(x>=128&&x<512&&(y==246||y==265))composed=24'hd6dbd1;
 end
 if(roi_border)composed=24'hb07934;
 if(busy&&y>=474)composed=24'hbd9757;
 if(error!=0&&y>=450&&y<456)composed=24'he35c66;
 if(!loading&&!zoom_on&&page==1&&y>=382&&y<390&&x>=352&&x<416)composed=(((x-352)*9)<((brightness+1)*64))?24'h386b59:24'hd6dbd1;
 if(!loading&&!zoom_on&&page==1&&y>=382&&y<390&&x>=464&&x<528)composed=(((x-464)*9)<((contrast+1)*64))?24'h386b59:24'hd6dbd1;
end
always @(posedge clk or posedge rst)begin
 if(rst)begin hd_photo<=0;hd_frac_y<=0;hd_footer_mode<=0;hd_px<=0;hd_py<=0;hd_text<=0;hd_glyph<=0;hd_x<=0;hd_y<=0;textaddr_pipe<=0;text_span1<=0;text_col1<=0;text_word<=0;text_space2<=1;xa<=0;ya<=0;txa<=0;tya<=0;x4<=0;y4<=0;bg4<=0;sync4<=0;tx4<=0;ty3<=0;valid4<=0;x<=0;y<=0;native_subx<=0;native_suby<=0;deold<=0;vsold<=0;frame<=0;fade<=0;busy_old<=1;begin glyph_override<=0;dict_override_valid<=1;end lineid<=0;bits<=0;sync1<=0;sync2<=0;sync3<=0;x1<=0;y1<=0;x2<=0;y2<=0;x3<=0;y3<=0;bg1<=0;bg2<=0;bg3<=0;ode<=0;ohs<=0;ovs<=0;rgb<=0;ensemble_seconds<=0;ensemble_next_second<=48000;seconds_frame<=0;sec_one<=0;sec_ten<=0;min_one<=0;min_ten<=0;scroll<=0;previous_page<=0;previous_inst<=0;previous_clip<=0;previous_detail<=0;visible_progress<=0;tx1<=0;tx2<=0;tx3<=0;ty1<=0;ty2<=0;valid1<=0;valid2<=0;valid3<=0;end
 else begin
 deold<=de;vsold<=vs;busy_old<=busy;
 if(!ensemble_on||progress==0)begin ensemble_seconds<=0;ensemble_next_second<=48000;end
 else if(progress>=ensemble_next_second&&ensemble_seconds<55)begin ensemble_seconds<=ensemble_seconds+1'b1;ensemble_next_second<=ensemble_next_second+48000;end
 if(vs&&!vsold)begin
  y<=0;native_suby<=0;frame<=frame+1'b1;visible_progress<=progress;if(fade<32)fade<=fade+1'b1;
  if(scroll==543)scroll<=0;else scroll<=scroll+1'b1;
  if(seconds_frame==(WIDE?29:59))begin seconds_frame<=0;
    if(sec_one==9)begin sec_one<=0;if(sec_ten==5)begin sec_ten<=0;
      if(min_one==9)begin min_one<=0;if(min_ten==9)min_ten<=0;else min_ten<=min_ten+1'b1;end
      else min_one<=min_one+1'b1;
    end else sec_ten<=sec_ten+1'b1;end else sec_one<=sec_one+1'b1;
  end else seconds_frame<=seconds_frame+1'b1;
 end
 if(de)begin
  if(WIDE!=1||native_subx==2)begin x<=x+1'b1;native_subx<=0;end else native_subx<=native_subx+1'b1;
 end else begin x<=0;native_subx<=0;end
 if(!de&&deold)begin
  if(!WIDE)y<=y+1'b1;
  else if(native_suby+4>=9)begin y<=y+1'b1;native_suby<=native_suby-5;end
  else native_suby<=native_suby+4;
 end
 if(page!=previous_page||instrument!=previous_inst||clip!=previous_clip||detail!=previous_detail)fade<=0;
 previous_page<=page;previous_inst<=instrument;previous_clip<=clip;previous_detail<=detail;
 lineid<=lines[lineaddr];textaddr_pipe<=textaddr;text_span1<=text_spans[textaddr[12:5]];text_col1<=textaddr[4:0];text_word<=text_data[text_byte_address];text_space2<=text_col1<text_span1[15:11]||text_col1>=text_span1[21:16];dict_override_valid<=0;if(!NATIVE_TEXT)bits<=font[{glyph,ty3[3:0]}];else bits<=0;
 if(stem_name1&&!settings&&!loading&&!mixpanel_on)begin glyph_override<=stem_name_glyph(stem_track1,stem_half1);dict_override_valid<=1;end 
 if(settings&&tya[8:4]==11&&txa[9:4]==25)begin glyph_override<=GLYPH_ZERO+brightness;dict_override_valid<=1;end 
 if(settings&&tya[8:4]==15&&txa[9:4]==25)begin glyph_override<=GLYPH_ZERO+contrast;dict_override_valid<=1;end 
 if(!loading&&!zoom_on&&page==1&&!settings&&ya[8:4]==26)begin glyph_override<=button_glyph(xa[9:4]);dict_override_valid<=1;end 
 if(zoom_on&&!loading&&txa[9:4]==8&&tya[8:4]==19)begin glyph_override<=GLYPH_ZERO+zoom_level+1'b1;dict_override_valid<=1;end 
 if(mixpanel_on)begin
  if(ya[8:4]==9&&(xa[9:4]==20||xa[9:4]==21))begin glyph_override<=stem_name_glyph(mix_track,xa[4]);dict_override_valid<=1;end 
  if(ya[8:4]==12&&xa[9:4]==20)begin glyph_override<=GLYPH_ZERO+(selected_volume>=10);dict_override_valid<=1;end 
  if(ya[8:4]==12&&xa[9:4]==21)begin glyph_override<=GLYPH_ZERO+((selected_volume>=10)?selected_volume-10:selected_volume);dict_override_valid<=1;end 
  if(ya[8:4]==15&&xa[9:4]==20)begin glyph_override<=dynamic_glyph(mix_mute[mix_track]?3:4);dict_override_valid<=1;end 
  if(ya[8:4]==18&&xa[9:4]==20)begin glyph_override<=dynamic_glyph(mix_solo==mix_track?3:4);dict_override_valid<=1;end 
  if(ya[8:4]==21&&xa[9:4]==20)begin glyph_override<=dynamic_glyph(mix_live?1:0);dict_override_valid<=1;end 
  if(ya[8:4]==21&&xa[9:4]==21)begin glyph_override<=mix_live?dynamic_glyph(2):stem_name_glyph(4,1);dict_override_valid<=1;end 
 end
 // Persistent physical build signature and actual SDRAM test result.
 if(test_failed&&ya[8:4]==0)begin
  begin glyph_override<=G_SPACE;dict_override_valid<=1;end 
  case(xa[9:4])
   1:begin glyph_override<=G_R;dict_override_valid<=1;end 2:begin glyph_override<=GLYPH_ZERO+1;dict_override_valid<=1;end 3:begin glyph_override<=GLYPH_ZERO+3;dict_override_valid<=1;end 
   6:begin glyph_override<=G_R;dict_override_valid<=1;end 7:begin glyph_override<=G_A;dict_override_valid<=1;end 8:begin glyph_override<=G_M;dict_override_valid<=1;end 
   10:begin glyph_override<=test_failed?G_F:(test_done?G_O:GLYPH_ZERO+test_stage);dict_override_valid<=1;end 
   11:begin glyph_override<=test_failed?G_A:(test_done?G_K:G_SPACE);dict_override_valid<=1;end 
   12:begin glyph_override<=test_failed?G_I:G_SPACE;dict_override_valid<=1;end 13:begin glyph_override<=test_failed?G_L:G_SPACE;dict_override_valid<=1;end 
  endcase
  if(test_failed)for(hex_digit=0;hex_digit<8;hex_digit=hex_digit+1)begin
   if(xa[9:4]==17+hex_digit)begin glyph_override<=hexglyph(test_expected>>(28-4*hex_digit));dict_override_valid<=1;end 
   if(xa[9:4]==28+hex_digit)begin glyph_override<=hexglyph(test_actual>>(28-4*hex_digit));dict_override_valid<=1;end 
  end
 end
 if(!intro_card&&page==3&&carousel&&ya[8:4]==1&&xa[9:4]>=10&&xa[9:4]<14)begin glyph_override<=carousel_glyph(xa[9:4]);dict_override_valid<=1;end 
 if(ya[8:4]==1)case(xa[9:4])
  33:begin glyph_override<=GLYPH_ZERO+(ensemble_on?0:min_ten);dict_override_valid<=1;end 34:begin glyph_override<=GLYPH_ZERO+(ensemble_on?0:min_one);dict_override_valid<=1;end 35:begin glyph_override<=GLYPH_COLON;dict_override_valid<=1;end 
  36:begin glyph_override<=GLYPH_ZERO+(ensemble_on?(ensemble_seconds/10):sec_ten);dict_override_valid<=1;end 37:begin glyph_override<=GLYPH_ZERO+(ensemble_on?(ensemble_seconds%10):sec_one);dict_override_valid<=1;end 
 endcase
 bg1<=composed;bg2<=bg1;bg3<=bg2;bg4<=bg3;x1<=x;y1<=y;x2<=x1;y2<=y1;x3<=x2;y3<=y2;sync1<={hs,vs,de};sync2<=sync1;sync3<=sync2;sync4<=sync3;x4<=x3;y4<=y3;xa<=x1;ya<=y1;txa<=tx1;tya<=ty1;
 tx1<=(WIDE==1)?{layout_x[9:4],native_font_column(native_font_phase)}:layout_x;tx2<=tx1;tx4<=tx3;tx3<=tx2;ty1<=layout_y;ty2<=ty1;ty3<=ty2;valid1<=layout_valid;valid2<=valid1;valid3<=valid2;valid4<=valid3;
 ode<=sync4[0];ovs<=sync4[1];ohs<=sync4[2];
 glyph4<=glyph;glyph_y4<=ty3[3:0];hd_glyph<=glyph4;hd_x<=tx4[3:0];hd_y<=glyph_y4;hd_text<=valid4;hd_photo<=ph4;hd_frac_y<=fy4;hd_footer_mode<=fm4;hd_px<=x4;hd_py<=y4;
 rgb<=(valid4&&bits[15-tx4[3:0]])?24'h293c34:bg4;
 if(stem_band3&&!settings&&!loading&&!mixpanel_on)begin
  hd_photo<=0;
  rgb<=(valid4&&bits[15-tx4[3:0]])?(stem_silent3?24'h91998f:24'h293c34):24'hf4f1e8;
  if(x4>=stem_left3+34&&x4<stem_left3+38&&y4>=stem_center3-2&&y4<stem_center3+2)rgb<=stem_silent3?24'hbd9757:24'h386b59;
  if(stem_line3&&y4>=stem_center3-stem_height&&y4<=stem_center3+stem_height)rgb<=24'h386b59;
 end
 if(footer_on4)hd_text<=0;
 if(footer_on4)rgb<=24'he8eadd;
 // Quiet parts form a fine centerline; each active column is exactly1px.
 if(!intro_card&&!loading&&!settings&&!zoom_on&&!mixpanel_on&&wave_ready&&page==1&&x4>=48&&x4<304&&y4==383)rgb<=24'hb7c8bb;
 if(!intro_card&&!loading&&!settings&&!zoom_on&&!mixpanel_on&&wave_ready&&page==3&&x4>=64&&x4<576&&y4==(ensemble_on?430:368))rgb<=24'hb7c8bb;
 if(!intro_card&&!loading&&!settings&&!zoom_on&&!mixpanel_on&&wave_ready&&page==1&&x4>=48&&x4<304&&!x4[0]&&y4>=383-wave_up&&y4<=383+wave_down)rgb<=24'h386b59;
 if(!intro_card&&!loading&&!settings&&!zoom_on&&!mixpanel_on&&wave_ready&&page==3&&x4>=64&&x4<576&&!x4[0]&&y4>=(ensemble_on?430:368)-wave_up&&y4<=(ensemble_on?430:368)+wave_down)rgb<=24'h386b59;
 end
end
endmodule
