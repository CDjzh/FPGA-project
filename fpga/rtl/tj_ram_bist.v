// Boot test checks actual DQ data, including 160 ms retention and all bank bits.
module tj_ram_bist(input clk,rst,input init_done,busy,refresh,
 output reg done,output reg failed,output reg[3:0] stage,
 output wr_en,rd_en,output[20:0] address,output[31:0] data,
 input rd_valid,input[31:0] rd_data,output reg[31:0] expected,actual);
reg[3:0] state;reg[2:0] region;reg[6:0] index;reg[23:0] timer;
reg[20:0] base;reg[20:0] check_address;
always @* case(region)
 0:base=0;1:base=256;2:base=512;3:base=768;
 4:base=307200;5:base=614400;6:base=1048576;default:base=1970112;
endcase
function[31:0] pattern;input[20:0] a;begin pattern=32'hc35a96e1^{a,11'd0}^{11'd0,a};end endfunction
assign address=base+index;
assign data=pattern(address);
assign wr_en=state==1&&!busy&&!refresh;
assign rd_en=state==4&&!busy&&!refresh;
always @(posedge clk or posedge rst)begin
 if(rst)begin state<=0;done<=0;failed<=0;stage<=0;region<=0;index<=0;timer<=0;expected<=0;actual<=0;check_address<=0;end
 else case(state)
 0:if(init_done)begin state<=1;stage<=1;end
 1:if(wr_en)begin state<=2;timer<=32;end
 2:if(timer!=0)timer<=timer-1'b1;else if(!busy&&!refresh)begin
  if(index==63)begin index<=0;if(region==7)begin state<=3;timer<=6400000;stage<=2;region<=0;end
   else begin region<=region+1'b1;state<=1;end
  end else begin index<=index+1'b1;state<=1;end
 end
 3:if(timer!=0)timer<=timer-1'b1;else begin state<=4;stage<=3;end
 4:if(rd_en)begin state<=5;check_address<=base;timer<=100000;end
 5:begin
  timer<=timer-1'b1;
  if(rd_valid)begin
   if(rd_data!==pattern(check_address))begin
    failed<=1;expected<=pattern(check_address);actual<=rd_data;state<=7;stage<=4;
   end else if(index==63)begin
    index<=0;if(region==7)begin done<=1;state<=6;stage<=5;end
    else begin region<=region+1'b1;state<=4;end
   end else begin index<=index+1'b1;check_address<=check_address+1'b1;end
  end else if(timer==0)begin failed<=1;state<=7;stage<=6;end
 end
 6:state<=6;
 7:state<=7;
 endcase
end
endmodule
