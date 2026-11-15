module BCD_ADDTHREE(
  input [3:0] input,
  output [3:0] output,
);
  assign output = input > 4 ? input + 3 : input;
endmodule

// double-dabble BCD encoder 
module BCD_ENCODER(
  input  [7:0]binary,
  output [3:0]decimal[2:0],
);
  wire [3:0] c1,c2,c3,c4,c5,c6,c7;
  wire [3:0] d1,d2,d3,d4,d5,d6,d7;

  assign d1 = {1'b0,A[7:5]};
  assign d2 = {c1[2:0],A[4]};
  assign d3 = {c2[2:0],A[3]};
  assign d4 = {c3[2:0],A[2]};
  assign d5 = {c4[2:0],A[1]};
  assign d6 = {1'b0,c1[3],c2[3],c3[3]};
  assign d7 = {c6[2:0],c4[3]};

  BCD_ADDTHREE m1(d1,c1);
  BCD_ADDTHREE m2(d2,c2);
  BCD_ADDTHREE m3(d3,c3);
  BCD_ADDTHREE m4(d4,c4);
  BCD_ADDTHREE m5(d5,c5);
  BCD_ADDTHREE m6(d6,c6);
  BCD_ADDTHREE m7(d7,c7);

  assign decimal[2] = {c5[2:0],A[0]}; // ones
  assign decimal[1] = {c7[2:0],c5[3]}; // tens
  assign decimal[0] = {c6[3],c7[3]}; // hundreds
endmodule

