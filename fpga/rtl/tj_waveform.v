// PCM extrema:384 samples per8ms column,256 chronological columns (2.048s).
// Freeze a complete display buffer during vertical blank; never edit it in DE.
module tj_waveform(input clk,rst,frame_tick,track_reset,playing,
 input signed[15:0] pcm,input pcm_valid,input[7:0] address,input pair_view,
 output[15:0] range_out,output reg ready);
reg[15:0] history[0:255];reg[31:0] display[0:127];reg[15:0] even_range;
reg signed[15:0] minimum,maximum;
wire signed[15:0] next_min=(pcm<minimum)?pcm:minimum;
wire signed[15:0] next_max=(pcm>maximum)?pcm:maximum;
reg[8:0] samples;reg[7:0] write_pointer,copy_index,copy_start;
reg[8:0] count,copy_count;reg copying;
wire[7:0] source_index=copy_start+copy_index;
wire commit_bin=pcm_valid&&playing&&!track_reset&&samples==383;
reg[31:0] packed_q1;reg half1;
wire[15:0] q1=half1?packed_q1[31:16]:packed_q1[15:0];
wire[15:0] q1b=packed_q1[31:16];
reg[15:0] q2,q3;reg pair1;
wire[7:0] paired_hi=(q1[15:8]>q1b[15:8])?q1[15:8]:q1b[15:8];
wire[7:0] paired_lo=(q1[7:0]<q1b[7:0])?q1[7:0]:q1b[7:0];
assign range_out=q3;
always @(posedge clk)begin
 packed_q1<=display[address[7:1]];half1<=address[0];pair1<=pair_view;
 q2<=pair1?{paired_hi,paired_lo}:q1;q3<=q2;
 if(copying)begin
 if(!copy_index[0])even_range<=(copy_index<copy_count)?history[source_index]:16'h8080;
 else display[copy_index[7:1]]<={(copy_index<copy_count)?history[source_index]:16'h8080,even_range};
end
 if(commit_bin)history[write_pointer]<={next_max[15:8]^8'h80,next_min[15:8]^8'h80};
end
always @(posedge clk or posedge rst)begin
 if(rst)begin minimum<=32767;maximum<=-32768;samples<=0;write_pointer<=0;count<=0;copying<=0;copy_index<=0;copy_start<=0;copy_count<=0;ready<=0;end
 else if(track_reset)begin minimum<=32767;maximum<=-32768;samples<=0;write_pointer<=0;count<=0;copying<=0;ready<=0;end
 else begin
  if(pcm_valid&&playing)begin
   minimum<=next_min;maximum<=next_max;
   if(samples==383)begin
    samples<=0;minimum<=32767;maximum<=-32768;write_pointer<=write_pointer+1'b1;if(count<256)count<=count+1'b1;
   end else samples<=samples+1'b1;
  end
  // Account for a bin committed on the same edge as the snapshot. During
  // the256-cycle copy at most one further bin can finish (384 samples/bin).
  // It can overwrite only the oldest entry, which the copy already consumed.
  if(frame_tick)begin
   copying<=1;copy_index<=0;
   // Compact view pairs are anchored to absolute even history bins.
   // Keep127 complete pairs after wrap, excluding the in-progress pair.
   if(pair_view)copy_start<=(count==256)?((write_pointer+commit_bin+1'b1)&8'hfe):0;
   else copy_start<=(count==256)?(write_pointer+commit_bin):0;
   if(pair_view)copy_count<=(count>=254)?254:((count+commit_bin)&9'h1fe);
   else copy_count<=(count<256&&commit_bin)?(count+1'b1):count;ready<=0;
  end
  else if(copying)begin
   if(copy_index==255)begin copying<=0;ready<=copy_count!=0;end
   else copy_index<=copy_index+1'b1;
  end
 end
end
endmodule
