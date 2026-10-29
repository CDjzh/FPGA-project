// R23 ensemble payload loader. Uses logical FAT file sectors, not physical LBAs.
module tj_ensemble_loader(input clk,rst,start,input cancel,
 output reg req,output reg[31:0] sector,input ready,output reg[6:0] wa,input[31:0] wd,
 output reg busy,loaded,output reg[7:0] error,output[4:0] progress,
 output wr_valid,input wr_ready,output[20:0] wr_addr,output[31:0] wr_data);
reg[4:0] state,ret;reg cached;reg[5:0] restart_hold;reg[31:0] word_latch,base_sector;reg[20:0] count;
assign progress=count[20:16];assign wr_valid=state==7;assign wr_addr=count;assign wr_data=word_latch;
task fetch;input[31:0] s;input[6:0] w;input[4:0] r;begin sector<=s;wa<=w;req<=1;ret<=r;state<=10;end endtask
always @(posedge clk or posedge rst)begin
 if(rst)begin state<=0;ret<=0;req<=0;sector<=0;wa<=0;busy<=0;loaded<=0;error<=0;count<=0;word_latch<=0;base_sector<=0;cached<=0;restart_hold<=0;end
 else begin
 if(cancel)begin loaded<=0;cached<=0;end
 if(cancel&&busy&&state!=14)begin req<=0;state<=14;end
 else
 case(state)
 0:if(start)begin busy<=1;loaded<=0;error<=0;count<=0;if(cached)begin restart_hold<=0;state<=15;end else fetch(0,10,1);end
 1:begin base_sector<=word_latch;wa<=11;ret<=2;state<=11;end
 2:begin req<=0;if(base_sector<8||word_latch!=32'h334e5345)begin error<=8'he1;busy<=0;state<=0;end else state<=3;end
 3:if(!ready)fetch(base_sector,0,4);
 4:begin
  if((wa==0&&word_latch!=32'h4e454a54)||(wa==1&&word_latch!=32'h35323053)||(wa==2&&word_latch!=2064120)||(wa==3&&word_latch!=2640000)||(wa==4&&word_latch!=744120))begin error<=8'he2;req<=0;busy<=0;state<=0;end
  else if(wa==4)begin req<=0;sector<=base_sector+1;state<=5;end
  else begin wa<=wa+1'b1;ret<=4;state<=11;end
 end
 5:if(!ready)fetch(sector,0,6);
 6:state<=7;
 7:if(wr_ready)begin
  count<=count+1'b1;
  if(count==2064119)begin req<=0;busy<=0;loaded<=1;cached<=1;state<=0;end
  else if(wa==127)begin req<=0;sector<=sector+1'b1;state<=5;end
  else begin wa<=wa+1'b1;ret<=6;state<=11;end
 end
 14:if(!ready)begin req<=0;busy<=0;loaded<=0;state<=0;end
 15:if(restart_hold==31)begin busy<=0;loaded<=1;state<=0;end else restart_hold<=restart_hold+1'b1;
 10:if(ready)state<=11;
 11:state<=12;
 12:state<=13;
 13:begin word_latch<=wd;state<=ret;end
 default:begin req<=0;busy<=0;error<=8'hef;state<=0;end
 endcase
 end
end
endmodule
