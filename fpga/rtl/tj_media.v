// Package v1 loader. RGB888 source images; signed PCM16LE mono 48 kHz.
// Writes are acknowledged individually, so an SD sector never overruns SDRAM arbitration.
module tj_media #(parameter INTRO_WIDTH=320)(input clk,rst,input mounted,input [7:0] fs_error,
 output reg req,output reg[31:0] sector,input ready,output reg[6:0] wa,input[31:0] wd,
 input start,input cancel,input carousel,input external_overwrite,input[1:0] page,instrument,input clip,input[1:0] detail,
 output reg busy,output reg done,output reg frame_ready,output reg[7:0] error,
 output reg[4:0] frame_index,output reg[20:0] audio_base,output reg[4:0] preload_progress,output reg audio_loaded,output reg[19:0] audio_samples,
 output wr_valid,input wr_ready,output[20:0] wr_addr,output[31:0] wr_data);
reg[31:0] sectors[0:47];reg[31:0] lengths[0:47];reg[19:0] samples[0:47];
reg[10:0] widths[0:47];reg[9:0] heights[0:47];reg[31:0] ids[0:47];
(* syn_encoding="onehot" *) reg[7:0] state;
reg[7:0] ret;reg[31:0] logical_sector;
(* syn_preserve=1,keep="true" *) reg[31:0] word_latch;
reg[9:0] word_index;reg[5:0] descriptor;reg[1:0] p,i,d;reg c;
reg[2:0] menu_inst;reg[1:0] backbuf;
reg[31:0] remaining;reg[8:0] byte_pos;reg[1:0] byte_lane,component;
reg[23:0] rgb;reg[7:0] sample_lo;
reg[10:0] sx;reg[9:0] sy;reg[9:0] dx,dy,xorigin,yorigin;
reg audio_kind;reg[20:0] base,write_address;reg[31:0] write_data;
reg[19:0] sample_index;
reg[31:0] requested_id,pack_sectors;
reg[31:0] cur_sector,cur_length,payload_sectors,range_end;
reg[10:0] cur_width;reg[9:0] cur_height;reg[19:0] cur_samples;
reg basic_bad,range_bad;reg[20:0] row_address;
(* syn_preserve=1,keep="true" *) reg[31:0] cached_id;
reg id_match;
reg[5:0] entry_count;reg[1:0] tour_slot,tour_shown;reg[31:0] packed_latch;reg[15:0] packed_sample;reg tour_ready,tour_loading,tour_active;reg[1:0] tour_target;
reg[19:0] tour_lengths[0:3];
function[20:0] tour_picture;input[1:0] n;begin tour_picture=n*333600;end endfunction
function[20:0] tour_sound;input[1:0] n;begin tour_sound=1334400+n*189600;end endfunction
reg index_valid;reg home_valid,audio_cached;reg[2:0] audio_key;
reg[2:0] cache_valid;reg[5:0] cache_key[0:2];
wire[5:0] picture_key={p,i,(p==2)?d:2'b00};
wire[2:0] sound_key={i,c};
localparam CHECK_CACHE=33,SOUND_SELECT=34,FINISH=35;

wire[7:0] b=word_latch>>(byte_lane*8);

localparam WAIT_MOUNT=0,GET_HEADER=1,CHECK_HEADER=2,GET_INDEX=3,INDEX_WORD=4,IDLE=5,SELECT=6,BEGIN_ASSET=7,GET_DATA=8,DATA_BYTE=9,WRITE=10,ASSET_DONE=11,
 IO_START=20,IO_WAIT=21,WORD_WAIT1=22,WORD_WAIT2=23,WORD_DONE=24,IO_RELEASE=25,FAIL=255;
assign wr_valid=state==WRITE;assign wr_addr=write_address;assign wr_data=write_data;
task fetch;input[31:0] sec;input[6:0] addr;input[7:0] next;begin
 sector<=sec;req<=1;wa<=addr;ret<=next;state<=IO_WAIT;end endtask
always @(posedge clk or posedge rst)begin
 if(rst)begin
 index_valid<=0;entry_count<=28;tour_slot<=0;tour_shown<=0;packed_latch<=0;packed_sample<=0;state<=WAIT_MOUNT;req<=0;sector<=0;wa<=0;busy<=1;done<=0;error<=0;frame_index<=0;audio_loaded<=0;audio_samples<=0;frame_ready<=0;home_valid<=0;audio_cached<=0;audio_key<=0;cache_valid<=0;audio_base<=1048576;preload_progress<=0;tour_ready<=0;tour_loading<=0;tour_active<=0;tour_target<=0;tour_lengths[0]<=0;tour_lengths[1]<=0;tour_lengths[2]<=0;tour_lengths[3]<=0;cache_key[0]<=0;cache_key[1]<=0;cache_key[2]<=0;
 word_index<=0;logical_sector<=0;descriptor<=0;menu_inst<=0;backbuf<=1;requested_id<=0;pack_sectors<=0;
 cur_sector<=0;cur_length<=0;payload_sectors<=0;range_end<=0;cur_width<=0;cur_height<=0;cur_samples<=0;basic_bad<=0;range_bad<=0;row_address<=0;
 cached_id<=0;id_match<=0;
 p<=0;i<=0;d<=0;c<=0;remaining<=0;byte_pos<=0;byte_lane<=0;component<=0;
 rgb<=0;sample_lo<=0;sx<=0;sy<=0;dx<=0;dy<=0;xorigin<=0;yorigin<=0;audio_kind<=0;base<=0;write_address<=0;write_data<=0;sample_index<=0;word_latch<=0;ret<=0;
 end else begin
 done<=0;frame_ready<=0;
 if(fs_error!=0)begin error<=fs_error;state<=FAIL;end
 else case(state)
 WAIT_MOUNT:if(mounted)begin word_index<=0;fetch(0,0,CHECK_HEADER);end
 CHECK_HEADER:begin
   if(word_index==5)entry_count<=word_latch[5:0];
   if((word_index==0 && word_latch!=32'h59464a54)||(word_index==1 && word_latch!=32'h314b4150)||
      (word_index==2 && word_latch!=8)||(word_index==3 && word_latch!=512)||(word_index==4 && word_latch!=64)||
      (word_index==5 && word_latch!=28 && word_latch!=44 && word_latch!=48)||(word_index==6 && word_latch!=1))begin error<=8'h10;state<=FAIL;end
   else if(word_index==8)begin pack_sectors<=word_latch;req<=0;word_index<=0;state<=GET_INDEX;end
   else begin word_index<=word_index+1'b1;wa<=wa+1'b1;state<=WORD_WAIT1;ret<=CHECK_HEADER;end
 end
 GET_INDEX:if(!ready)fetch(1+(word_index>>7),word_index[6:0],INDEX_WORD);
 INDEX_WORD:begin
  case(word_index[3:0])
   0:ids[word_index>>4]<=word_latch;
   4:widths[word_index>>4]<=word_latch[10:0];
   5:heights[word_index>>4]<=word_latch[9:0];
   7:samples[word_index>>4]<=word_latch[19:0];
   8:sectors[word_index>>4]<=word_latch;
   9:lengths[word_index>>4]<=word_latch;
  endcase
  if(word_index==entry_count*16-1)begin index_valid<=1;req<=0;busy<=0;state<=IDLE;end
  else begin
   word_index<=word_index+1'b1;wa<=wa+1'b1;
   if(word_index[6:0]==127)begin req<=0;state<=GET_INDEX;end
   else begin state<=WORD_WAIT1;ret<=INDEX_WORD;end
  end
 end
 IDLE:if(carousel&&tour_ready&&!start&&detail!=tour_shown)begin frame_index<=8+tour_target*4+detail;tour_shown<=detail;frame_ready<=1;end else if(start)begin
   busy<=1;p<=page;i<=instrument;c<=clip;d<=detail;menu_inst<=0;
   if(carousel)begin
    tour_active<=1;tour_target<=instrument;tour_shown<=0;
    if(tour_ready)state<=36;
    else begin tour_loading<=1;home_valid<=0;i<=0;c<=1;tour_slot<=0;cache_valid<=0;audio_cached<=0;audio_loaded<=0;preload_progress<=0;state<=SELECT;end
   end else begin
    tour_loading<=0;
    if(tour_active)begin tour_ready<=0;cache_valid<=0;audio_cached<=0;audio_loaded<=0;tour_active<=0;end
    audio_base<=1048576;state<=CHECK_CACHE;
   end
   if(page!=0)begin if(frame_index==1)backbuf<=2;else backbuf<=1;end
 end
 36:begin
  frame_index<=8+tour_target*4;audio_base<=tour_sound(tour_target);audio_samples<=tour_lengths[tour_target];audio_loaded<=1;frame_ready<=1;tour_loading<=0;state<=FINISH;
 end
 CHECK_CACHE:begin
  if(p==0&&home_valid)begin backbuf<=0;frame_index<=0;frame_ready<=1;state<=SOUND_SELECT;end
  else if(p!=0&&cache_valid[1]&&cache_key[1]==picture_key)begin backbuf<=1;frame_index<=1;frame_ready<=1;state<=SOUND_SELECT;end
  else if(p!=0&&cache_valid[2]&&cache_key[2]==picture_key)begin backbuf<=2;frame_index<=2;frame_ready<=1;state<=SOUND_SELECT;end
  else begin if(p!=0)cache_valid[backbuf]<=0;state<=SELECT;end
 end
 SOUND_SELECT:begin
  if((p==1||p==3)&&(!audio_cached||audio_key!=sound_key))begin
   audio_loaded<=0;audio_cached<=0;requested_id<=32'h2000+i*16+c;descriptor<=0;audio_kind<=1;state<=26;
  end else state<=FINISH;
 end
 FINISH:begin busy<=0;done<=1;state<=IDLE;end
 SELECT:begin
  if(p==0)begin requested_id<=32'h1004+menu_inst*16;base<=0;xorigin<=menu_inst[0]?360:40;yorigin<=menu_inst[1]?250:48;end
  else begin
   requested_id<=((p==1)?32'h4000:32'h1000)+i*16+((p==2)?(1+d):0);base<=(backbuf==1)?307200:614400;xorigin<=(p==3)?0:16;yorigin<=(p==3)?0:((p==1)?80:88);
  end
  if(tour_loading)requested_id<=32'h3000+i*16+tour_slot;
  audio_kind<=0;descriptor<=0;state<=26;
  if(p==0)case(menu_inst)
   0:row_address<=30760;1:row_address<=31080;2:row_address<=160040;3:row_address<=160360;
  endcase
  else row_address<=tour_loading?(tour_picture(i)+((tour_slot==0)?0:(153600+(tour_slot-1)*60000))):(((backbuf==1)?307200:614400)+((p==3)?0:((p==1)?51216:56336)));
 end
 26:begin cached_id<=ids[descriptor];state<=31;end
 31:begin id_match<=cached_id==requested_id;state<=32;end
 32:if(id_match)state<=27;
    else if(descriptor==entry_count-1)begin error<=8'h12;state<=FAIL;end
    else begin descriptor<=descriptor+1'b1;state<=26;end
 27:begin
  cur_sector<=sectors[descriptor];cur_length<=lengths[descriptor];cur_width<=widths[descriptor];cur_height<=heights[descriptor];cur_samples<=samples[descriptor];state<=28;
 end
 28:begin
  payload_sectors<=(cur_length>>9)+(|cur_length[8:0]);
  basic_bad<=cur_sector<8 || cur_length==0 || (audio_kind && (cur_samples==0 || cur_samples>921600 || cur_length!={cur_samples,1'b0})) || (!audio_kind && (cur_width==0 || cur_height==0));state<=29;
 end
 29:begin range_end<=cur_sector+payload_sectors;state<=30;end
 30:begin range_bad<=range_end>pack_sectors;state<=BEGIN_ASSET;end
 BEGIN_ASSET:begin
   if(basic_bad||range_bad||(tour_loading&&!audio_kind&&(((tour_slot==0)&&(cur_width!=640||cur_height!=480||cur_length!=614400))||((tour_slot!=0)&&(cur_width!=400||cur_height!=300||cur_length!=240000)))))begin error<=8'h11;state<=FAIL;end
   else begin
   logical_sector<=cur_sector;remaining<=(tour_loading&&audio_kind)?(((cur_samples>379200)?32'd379200:{12'd0,cur_samples})<<1):cur_length;byte_pos<=0;byte_lane<=0;component<=0;sx<=0;sy<=0;dx<=0;dy<=0;sample_index<=0;
   if(!audio_kind&&!tour_loading&&((p==0&&(cur_width!=240||cur_height!=180))||(p==1&&(cur_width!=320||cur_height!=240))||(p==2&&(cur_width!=400||cur_height!=300))||(p==3&&(cur_width!=640||cur_height!=480))))begin error<=8'h12;state<=FAIL;end
   else
   state<=GET_DATA;
   end
 end
 GET_DATA:if(!ready)begin
  if(cancel)begin busy<=0;req<=0;tour_loading<=0;tour_ready<=0;state<=IDLE;end
  else fetch(logical_sector,0,DATA_BYTE);
 end
 DATA_BYTE:begin
   // 32-bit synchronous sector buffer is latched before byte extraction.
   if(tour_loading&&!audio_kind)begin
    packed_latch<=packed_latch | ({24'd0,b}<<(component*8));
    if(component==3)begin component<=0;write_data<={b,packed_latch[23:0]};write_address<=row_address+sample_index;sample_index<=sample_index+1'b1;packed_latch<=0;state<=WRITE;end
    else component<=component+1'b1;
   end else if(audio_kind)begin
     if(component==0)begin sample_lo<=b;component<=1;end
     else begin component<=0;sample_index<=sample_index+1'b1;
      if(tour_loading)begin
       if(!sample_index[0])packed_sample<={b,sample_lo};
       if(sample_index[0]||remaining==1)begin write_address<=tour_sound(i)+(sample_index>>1);write_data<=sample_index[0]?{b,sample_lo,packed_sample}:{16'd0,b,sample_lo};state<=WRITE;end
      end else begin write_address<={1'b1,sample_index};write_data<={16'd0,b,sample_lo};state<=WRITE;end
     end
   end else begin
    case(component)
     0:begin rgb[23:16]<=b;component<=1;end
     1:begin rgb[15:8]<=b;component<=2;end
     2:begin
      component<=0;
      write_address<=row_address+dx;write_data<={rgb[23:8],b,8'd0};state<=WRITE;dx<=dx+1'b1;
      if(sx+1==cur_width)begin sx<=0;sy<=sy+1'b1;dx<=0;dy<=dy+1'b1;row_address<=row_address+640;end
      else sx<=sx+1'b1;
     end
    endcase
   end
   remaining<=remaining-1'b1;byte_pos<=byte_pos+1'b1;byte_lane<=byte_lane+1'b1;
   if(!((tour_loading&&!audio_kind&&component==3)||(audio_kind&&component==1&&(!tour_loading||sample_index[0]||remaining==1))||(!tour_loading&&!audio_kind&&component==2)))begin
    if(remaining==1)begin req<=0;state<=ASSET_DONE;end
    else if(byte_pos==511)begin req<=0;logical_sector<=logical_sector+1'b1;state<=GET_DATA;end
    else if(byte_lane==3)begin wa<=wa+1'b1;ret<=DATA_BYTE;state<=WORD_WAIT1;end
   end
 end
 WRITE:if(wr_ready)begin
   if(remaining==0)begin req<=0;state<=ASSET_DONE;end
   else if(byte_pos==0)begin req<=0;logical_sector<=logical_sector+1'b1;state<=GET_DATA;end
   else if(byte_lane==0)begin wa<=wa+1'b1;ret<=DATA_BYTE;state<=WORD_WAIT1;end
   else state<=DATA_BYTE;
 end
 ASSET_DONE:begin
  if(tour_loading)begin
   preload_progress<=preload_progress+1'b1;
   if(!audio_kind&&tour_slot<3)begin tour_slot<=tour_slot+1'b1;state<=SELECT;end
   else if(!audio_kind)begin requested_id<=32'h2001+i*16;descriptor<=0;audio_kind<=1;state<=26;end
   else begin
    tour_lengths[i]<=(cur_samples>379200)?379200:cur_samples;
    if(i!=3)begin i<=i+1'b1;tour_slot<=0;state<=SELECT;end
    else begin tour_ready<=1;state<=36;end
   end
  end else if(p==0 && menu_inst<3)begin menu_inst<=menu_inst+1'b1;state<=SELECT;end
  else if(!audio_kind)begin
   frame_index<=(p==0)?0:backbuf;frame_ready<=1;
   if(p==0)home_valid<=1;
   else begin cache_valid[backbuf]<=1;cache_key[backbuf]<=picture_key;end
   state<=SOUND_SELECT;
  end else begin
   audio_samples<=cur_samples;audio_loaded<=1;audio_cached<=1;audio_key<=sound_key;state<=FINISH;
  end
 end
 IO_WAIT:if(ready)state<=WORD_WAIT1;
 WORD_WAIT1:state<=WORD_WAIT2;
 WORD_WAIT2:begin word_latch<=wd;state<=ret;end
 FAIL:begin req<=0;busy<=0;end
 default:state<=FAIL;
 endcase
 if(external_overwrite===1'b1)begin state<=index_valid?IDLE:WAIT_MOUNT;busy<=!index_valid;req<=0;home_valid<=0;cache_valid<=0;audio_cached<=0;audio_loaded<=0;tour_ready<=0;tour_active<=0;end
 end
end
endmodule
