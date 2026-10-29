// Gray-pointer FIFO; synchronous read, valid asserted with the corresponding data.
module tj_async_fifo #(parameter W=32,A=9)(input rst,wclk,rclk,we,re,input[W-1:0] din,
 output reg[W-1:0] dout,output reg valid,output full,empty,output[A:0] used);
reg[W-1:0] mem[0:(1<<A)-1];reg[A:0] wp,rp,wg,rg;
(* async_reg="true" *)reg[A:0] rg1,rg2,wg1,wg2;
wire[A:0] wn=wp+1'b1;wire[A:0] wgn=(wn>>1)^wn;
assign full=wgn=={~rg2[A:A-1],rg2[A-2:0]};assign empty=rg==wg2;
function[A:0] ungray;input[A:0] g;integer j;begin ungray[A]=g[A];for(j=A-1;j>=0;j=j-1)ungray[j]=ungray[j+1]^g[j];end endfunction
assign used=wp-ungray(rg2);
always @(posedge wclk or posedge rst)if(rst)begin wp<=0;wg<=0;rg1<=0;rg2<=0;end
else begin rg1<=rg;rg2<=rg1;if(we&&!full)begin mem[wp[A-1:0]]<=din;wp<=wn;wg<=wgn;end end
always @(posedge rclk or posedge rst)if(rst)begin rp<=0;rg<=0;wg1<=0;wg2<=0;dout<=0;valid<=0;end
else begin wg1<=wg;wg2<=wg1;valid<=re&&!empty;if(re&&!empty)begin dout<=mem[rp[A-1:0]];rp<=rp+1'b1;rg<=((rp+1'b1)>>1)^(rp+1'b1);end end
endmodule
