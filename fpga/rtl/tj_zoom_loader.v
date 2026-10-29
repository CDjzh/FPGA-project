// V6 native1280x960 RGB565 plus224x168 overview. Dedicated cache, no CPU.
module tj_zoom_loader(input clk,rst,enable,input[1:0] instrument,
 output reg req,output reg[31:0] sector,input ready,output reg[6:0] wa,input[31:0] wd,
 output wr_valid,input wr_ready,output[20:0] wr_addr,output[31:0] wr_data,
 output reg loaded,output reg[7:0] error,output[4:0] progress);
reg[3:0] state;reg[19:0] count;reg[31:0] base,latch;
assign wr_valid=enable&&state==5;assign wr_addr={1'b0,count};assign wr_data=latch;assign progress=count[19:15];
always @(posedge clk or posedge rst)begin
 if(rst)begin state<=0;req<=0;sector<=0;wa<=0;count<=0;base<=0;latch<=0;loaded<=0;error<=0;end
 else if(!enable)begin req<=0;state<=0;count<=0;loaded<=0;error<=0;end
 else case(state)
 0:if(!ready)begin sector<=0;wa<=14;req<=1;state<=1;end
 1:if(ready)state<=2;
 2:state<=3;
 3:begin base<=wd+instrument*4947;wa<=15;state<=7;end
 7:state<=13;
 13:state<=8;
 8:begin if(wd!=32'h364d4f5a)begin error<=8'hf6;state<=15;end else begin req<=0;state<=9;end end
 9:if(!ready)begin sector<=base+(count>>7);wa<=0;req<=1;state<=10;end
 10:if(ready)state<=11;
 11:state<=12;
 12:state<=14;
 14:begin latch<=wd;state<=5;end
 5:if(wr_ready)begin
  count<=count+1'b1;
  if(count==633215)begin loaded<=1;req<=0;state<=15;end
  else if(wa==127)begin req<=0;state<=9;end
  else begin wa<=wa+1'b1;state<=11;end
 end
 15:req<=0;
 default:state<=0;
 endcase
end
endmodule
