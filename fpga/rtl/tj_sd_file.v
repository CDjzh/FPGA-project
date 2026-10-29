// Read-only FAT32 sector service. Walks directory/file FAT chains, including fragmentation.
// Client owns the 128-word sector buffer only while ready is asserted.
module tj_sd_file(input clk,rst,input card_ready,
 output reg sd_req,output reg [31:0] sd_lba,input [7:0] sd_byte,input sd_valid,sd_end,
 input req,input [31:0] file_sector,output reg ready,output reg mounted,
 input [6:0] word_addr,output reg [31:0] word_data,output reg [7:0] error,output idle);
reg [31:0] buffer[0:127];
reg [8:0] byte_count;reg [23:0] assembly;
reg [6:0] scan;(* syn_preserve=1,keep="true" *) reg [31:0] q;reg [31:0] q_stage;
reg [7:0] state,after_io,scan_kind,after_fat;
reg [31:0] partition,fat_base,data_base,fat_size,root_cluster;
reg [7:0] spc;reg [3:0] spc_shift;
reg [31:0] dir_cluster,file_cluster,walk_cluster,walk_index,target_index,target_sector;
reg [7:0] dir_sector;reg directory_level;
reg [31:0] dir_start;reg match_name,entry_valid;reg [15:0] cluster_hi;
reg [31:0] bpb_reserved,bpb_fats,bpb_flags;
reg [31:0] fat_query;reg [31:0] loop_count;reg [28:0] watchdog;
reg [31:0] cluster_work,sector_base,fat_span,primary_fat;
localparam IDLE=0,IO=1,SCAN_SETUP=2,SCAN_WAIT=3,SCAN_USE=4,BPB_DONE=5,DIR_NEXT=6,FAT_BEGIN=7,FAT_DONE=8,FILE_IDLE=9,FILE_WALK=10,FILE_READ=11,FILE_READY=12,FAIL=255;
assign idle=state==FILE_IDLE;
always @(posedge clk) begin
 word_data<=buffer[word_addr]; q_stage<=buffer[scan];q<=q_stage;
 if(sd_valid && state==IO) begin
   case(byte_count[1:0])
    0:assembly[7:0]<=sd_byte;1:assembly[15:8]<=sd_byte;2:assembly[23:16]<=sd_byte;
    3:buffer[byte_count[8:2]]<={sd_byte,assembly};
   endcase
 end
end
task io_read;input [31:0] lba;input [7:0] ret;begin sd_lba<=lba;sd_req<=1;byte_count<=0;after_io<=ret;state<=IO;end endtask
always @(posedge clk or posedge rst) begin
 if(rst) begin
 state<=IDLE;sd_req<=0;sd_lba<=0;ready<=0;mounted<=0;error<=0;partition<=0;byte_count<=0;
 scan<=0;scan_kind<=0;directory_level<=0;dir_sector<=0;walk_index<=0;walk_cluster<=0;
 watchdog<=0;loop_count<=0;fat_query<=0;target_index<=0;target_sector<=0;
 spc<=0;spc_shift<=0;fat_base<=0;data_base<=0;fat_size<=0;root_cluster<=0;
 bpb_reserved<=0;bpb_fats<=0;bpb_flags<=0;dir_cluster<=0;file_cluster<=0;
 dir_start<=0;match_name<=0;entry_valid<=0;cluster_hi<=0;after_io<=0;after_fat<=0;
 cluster_work<=0;sector_base<=0;fat_span<=0;primary_fat<=0;
 end else begin
 if(state==IO || state==IDLE) watchdog<=watchdog+1'b1;else watchdog<=0;
 if(&watchdog)begin error<=8'h01;state<=FAIL;sd_req<=0;end
 else case(state)
 IDLE:if(card_ready)begin scan_kind<=0;io_read(0,SCAN_SETUP);end
 IO:begin
  if(sd_valid) byte_count<=byte_count+1'b1;
  if(sd_end)begin sd_req<=0;state<=after_io;end
 end
 SCAN_SETUP:begin scan<=0;state<=SCAN_WAIT;end
 SCAN_WAIT:state<=13;
 13:state<=SCAN_USE;
 SCAN_USE:begin
   state<=SCAN_WAIT;scan<=scan+1'b1;
   case(scan_kind)
    0,1:begin
      // BPB fields can be unaligned across words.
      case(scan)
      2:spc<=q[31:24]; // temporary low byte of bytes-per-sector
      3:begin
         if({q[7:0],spc}==16'd512)spc<=q[15:8];else spc<=0;
         bpb_reserved<=q[31:16];
        end
      4:bpb_fats<=q[7:0];
      9:fat_size<=q;
      10:bpb_flags<=q[15:0];
      11:root_cluster<=q;
      113:if(scan_kind==0)partition[15:0]<=q[31:16];
      114:if(scan_kind==0)partition[31:16]<=q[15:0];
      endcase
      if(scan==127)begin
        if(scan_kind==0 && spc==0) begin scan_kind<=1;io_read(partition,SCAN_SETUP);end
        else begin if(scan_kind==0)partition<=0;state<=BPB_DONE;end
      end
    end
    2:begin
      case(scan[2:0])
       0:begin
         entry_valid<=(q[7:0]!=0 && q[7:0]!=8'he5);
         match_name<=directory_level ? q==32'h45535341 : q==32'h474e4954;
         if(q[7:0]==0) begin error<=8'h04;state<=FAIL;end
       end
       1:match_name<=match_name && (directory_level ? q==32'h20205354 : q==32'h4e41494a);
       2:match_name<=match_name && (directory_level ? (q[23:0]==24'h4e4942 && !q[28] && q[29:24]!=6'h0f) : (q[23:0]==24'h202020 && q[28]));
       5:cluster_hi<=q[15:0];
       6:dir_start<={cluster_hi,q[31:16]};
       7:if(entry_valid && match_name)begin
         if(directory_level)begin file_cluster<=dir_start;walk_cluster<=dir_start;walk_index<=0;mounted<=1;state<=FILE_IDLE;end
         else begin directory_level<=1;dir_cluster<=dir_start;dir_sector<=0;state<=DIR_NEXT;end
       end
      endcase
      if(scan==127 && !(entry_valid && match_name))begin
        if(dir_sector+1<spc)begin dir_sector<=dir_sector+1'b1;state<=DIR_NEXT;end
        else begin fat_query<=dir_cluster;after_fat<=DIR_NEXT;state<=FAT_BEGIN;end
      end
    end
    3:begin
      // FAT sector only needs one selected 32-bit entry.
      if(scan==fat_query[6:0])begin
       if(q[27:0]<2 || q[27:0]>=28'hffffff8 || loop_count>32'd1048576)begin error<=8'h05;state<=FAIL;end
       else begin
        if(after_fat==DIR_NEXT)begin dir_cluster<={4'b0,q[27:0]};dir_sector<=0;end
        else begin walk_cluster<={4'b0,q[27:0]};walk_index<=walk_index+1'b1;end
        state<=after_fat;
       end
      end
    end
   endcase
 end
 BPB_DONE:begin
   if(spc==0 || (spc & (spc-1))!=0 || bpb_fats<1 || bpb_fats>2 || fat_size==0 || root_cluster<2)begin error<=8'h03;state<=FAIL;end
   else begin
    case(spc)1:spc_shift<=0;2:spc_shift<=1;4:spc_shift<=2;8:spc_shift<=3;16:spc_shift<=4;32:spc_shift<=5;64:spc_shift<=6;128:spc_shift<=7;default:spc_shift<=0;endcase
    primary_fat<=partition+bpb_reserved;
    fat_span<=(bpb_fats==2)?(fat_size<<1):fat_size;dir_cluster<=root_cluster;state<=20;
   end
 end
 20:begin fat_base<=primary_fat+((bpb_flags[7]&&bpb_flags[0])?fat_size:0);data_base<=primary_fat+fat_span;state<=DIR_NEXT;end
 DIR_NEXT:begin cluster_work<=dir_cluster-2;state<=14;end
 14:begin cluster_work<=cluster_work<<spc_shift;state<=15;end
 15:begin sector_base<=data_base+cluster_work;state<=16;end
 16:begin scan_kind<=2;io_read(sector_base+dir_sector,SCAN_SETUP);end
 FAT_BEGIN:begin scan_kind<=3;loop_count<=loop_count+1'b1;io_read(fat_base+(fat_query>>7),SCAN_SETUP);end
 FILE_IDLE:if(req)begin
   ready<=0;target_sector<=file_sector;target_index<=file_sector>>spc_shift;loop_count<=0;
   if((file_sector>>spc_shift)<walk_index)begin walk_cluster<=file_cluster;walk_index<=0;end
   state<=FILE_WALK;
 end
 FILE_WALK:if(walk_index==target_index)state<=FILE_READ;
   else begin fat_query<=walk_cluster;after_fat<=FILE_WALK;state<=FAT_BEGIN;end
 FILE_READ:begin cluster_work<=walk_cluster-2;state<=17;end
 17:begin cluster_work<=cluster_work<<spc_shift;state<=18;end
 18:begin sector_base<=data_base+cluster_work;state<=19;end
 19:io_read(sector_base+(target_sector & (spc-1)),FILE_READY);
 FILE_READY:begin ready<=1;if(!req)begin state<=FILE_IDLE;ready<=0;end end
 FAIL:begin sd_req<=0;ready<=0;end
 default:state<=FAIL;
 endcase
 end
end
endmodule
