localparam BUTTON_WIDTH=104;
function[9:0] button_left;input[2:0] n;begin case(n)
0:button_left=10'd16;
1:button_left=10'd128;
2:button_left=10'd240;
3:button_left=10'd352;
4:button_left=10'd464;
default:button_left=16;endcase end endfunction
function[7:0] button_glyph;input[5:0] col;begin case(col)
3:button_glyph=8'd91;
4:button_glyph=8'd247;
5:button_glyph=8'd26;
10:button_glyph=8'd91;
11:button_glyph=8'd247;
12:button_glyph=8'd37;
17:button_glyph=8'd183;
18:button_glyph=8'd199;
19:button_glyph=8'd210;
24:button_glyph=8'd52;
25:button_glyph=8'd105;
31:button_glyph=8'd138;
32:button_glyph=8'd94;
default:button_glyph=8'd0;endcase end endfunction
function[7:0] carousel_glyph;input[5:0] col;begin case(col)
10:carousel_glyph=8'd115;
11:carousel_glyph=8'd173;
12:carousel_glyph=8'd106;
13:carousel_glyph=8'd134;
default:carousel_glyph=8'd0;endcase end endfunction
function[7:0] stem_name_glyph;input[2:0] track;input half;begin case({track,half})
4'd0:stem_name_glyph=8'd73;
4'd1:stem_name_glyph=8'd194;
4'd2:stem_name_glyph=8'd176;
4'd3:stem_name_glyph=8'd177;
4'd4:stem_name_glyph=8'd37;
4'd5:stem_name_glyph=8'd206;
4'd6:stem_name_glyph=8'd191;
4'd7:stem_name_glyph=8'd192;
4'd8:stem_name_glyph=8'd41;
4'd9:stem_name_glyph=8'd91;
default:stem_name_glyph=G_SPACE;endcase end endfunction
function[7:0] dynamic_glyph;input[3:0] n;begin case(n)
0:dynamic_glyph=8'd69;
1:dynamic_glyph=8'd101;
2:dynamic_glyph=8'd141;
3:dynamic_glyph=8'd109;
4:dynamic_glyph=8'd55;
5:dynamic_glyph=8'd50;
6:dynamic_glyph=8'd237;
7:dynamic_glyph=8'd244;
8:dynamic_glyph=8'd171;
9:dynamic_glyph=8'd140;
10:dynamic_glyph=8'd94;
11:dynamic_glyph=8'd110;
12:dynamic_glyph=8'd27;
13:dynamic_glyph=8'd232;
default:dynamic_glyph=G_SPACE;endcase end endfunction
