// R18: registered passthrough. Loading has a dedicated vector/text screen.
module tj_loading_preview(input clk,rst,de,hs,vs,input[23:0] photo,
 input capture_home,loading,has_frame,output reg ode,ohs,ovs,output reg[23:0] out_photo);
always @(posedge clk or posedge rst)begin
 if(rst)begin ode<=0;ohs<=0;ovs<=0;out_photo<=24'hf4f1e8;end
 else begin ode<=de;ohs<=hs;ovs<=vs;out_photo<=has_frame&&!loading?photo:24'hf4f1e8;end
end
endmodule
