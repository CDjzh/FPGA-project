// Explicit JEDEC command sequencing, 40 MHz, CAS=2, full-page sequential read,
// single-location writes. Requests are owned until precharge has completed.
module tj_sdram(input Clk,Clk_sft,Rst,
 output reg Sdr_init_done,output Sdr_init_ref_vld,output Sdr_busy,
 input App_wr_en,input[20:0] App_wr_addr,input[3:0] App_wr_dm,input[31:0] App_wr_din,
 input App_rd_en,input[20:0] App_rd_addr,input[6:0] App_rd_count,
 output reg Sdr_rd_en,output reg[31:0] Sdr_rd_dout,
 output reg ras_n,cas_n,we_n,output reg[10:0] addr,output reg[1:0] ba,
 output reg[3:0] dm,inout[31:0] dq);
localparam POWER=0,PRE=1,INIT_REF=2,MODE=3,IDLE=4,ACT=5,WRITE=6,
 READ=7,READ_WAIT=8,READ_DATA=9,STOP=10,CLOSE=11,SETTLE=12,REFRESH=13,WAIT=14;
reg[3:0] state,after_wait;reg[13:0] delay_count;reg[10:0] refresh_count;
reg[3:0] init_refs;reg[20:0] request_addr;reg[31:0] request_data;
reg[3:0] request_dm;reg is_read;reg[6:0] words_left;
reg drive;reg[31:0] dqout;
assign dq=drive?dqout:32'bz;
assign Sdr_busy=state!=IDLE || refresh_count>=1199;
assign Sdr_init_ref_vld=!Sdr_init_done || refresh_count>=1199 || state==REFRESH;
always @(posedge Clk or posedge Rst)begin
 if(Rst)begin state<=POWER;after_wait<=IDLE;delay_count<=10000;refresh_count<=0;init_refs<=0;
 request_addr<=0;request_data<=0;request_dm<=0;is_read<=0;words_left<=0;
 drive<=0;dqout<=0;ras_n<=1;cas_n<=1;we_n<=1;addr<=0;ba<=0;dm<=0;
 Sdr_init_done<=0;Sdr_rd_en<=0;Sdr_rd_dout<=0;end
 else begin
 ras_n<=1;cas_n<=1;we_n<=1;drive<=0;Sdr_rd_en<=0;dm<=0;
 if(Sdr_init_done && refresh_count<2047)refresh_count<=refresh_count+1'b1;
 case(state)
 POWER:if(delay_count==0)state<=PRE;else delay_count<=delay_count-1'b1;
 PRE:begin ras_n<=0;we_n<=0;addr<=11'h400;delay_count<=3;after_wait<=INIT_REF;state<=WAIT;end
 INIT_REF:begin ras_n<=0;cas_n<=0;init_refs<=init_refs+1'b1;
  delay_count<=4;after_wait<=(init_refs==7)?MODE:INIT_REF;state<=WAIT;end
 MODE:begin ras_n<=0;cas_n<=0;we_n<=0;ba<=0;addr<=11'h227;
  delay_count<=3;after_wait<=IDLE;state<=WAIT;Sdr_init_done<=1;refresh_count<=0;end
 IDLE:begin
  if(refresh_count>=1199)state<=REFRESH;
  else if(App_wr_en || App_rd_en)begin
   is_read<=App_rd_en;request_addr<=App_rd_en?App_rd_addr:App_wr_addr;
   request_data<=App_wr_din;request_dm<=App_wr_dm;
   words_left<=App_rd_count;state<=ACT;
  end
 end
 ACT:begin ras_n<=0;addr<=request_addr[20:10];ba<=request_addr[9:8];
  delay_count<=1;after_wait<=is_read?READ:WRITE;state<=WAIT;end
 WRITE:begin cas_n<=0;we_n<=0;addr<={3'b000,request_addr[7:0]};
  dqout<=request_data;drive<=1;dm<=request_dm;
  delay_count<=2;after_wait<=CLOSE;state<=WAIT;end
 // Capture the first CL=2 word one host cycle earlier. R12 read address+1
 // as its first word (hardware evidence: C35A96E1 -> C35A9EE0).
 READ:begin cas_n<=0;addr<={3'b000,request_addr[7:0]};delay_count<=1;state<=READ_WAIT;end
 READ_WAIT:if(delay_count==0)begin
  Sdr_rd_dout<=dq;Sdr_rd_en<=1;words_left<=words_left-1'b1;
  state<=(words_left==1)?STOP:READ_DATA;
 end else delay_count<=delay_count-1'b1;
 READ_DATA:begin Sdr_rd_dout<=dq;Sdr_rd_en<=1;words_left<=words_left-1'b1;
  if(words_left==1)state<=STOP;end
 STOP:begin we_n<=0;delay_count<=2;after_wait<=CLOSE;state<=WAIT;end
 CLOSE:begin ras_n<=0;we_n<=0;addr<=11'h400;delay_count<=2;after_wait<=IDLE;state<=WAIT;end
 REFRESH:begin ras_n<=0;cas_n<=0;refresh_count<=0;delay_count<=4;after_wait<=IDLE;state<=WAIT;end
 WAIT:if(delay_count==0)state<=after_wait;else delay_count<=delay_count-1'b1;
 default:state<=POWER;
 endcase
 end
end
endmodule
