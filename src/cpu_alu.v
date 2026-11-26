// anticipating full adder
module CPU_ALU_ant_fa(input c_in, input a, b, output sum, output prop, output gen);
    assign prop = a | b;
    assign gen = a & b;
    assign sum = a ^ b ^ c_in;
endmodule

// a carry-lookahead adder
module CPU_ALU_adder(input c_in, input [7:0] a, b, output [7:0] sum, output c_out);
  wire [7:0] prop;
  wire [7:0] gen;
  wire [6:0] c_ant; // anticipated carry

  CPU_ALU_ant_fa a1(c_in, a[0], b[0], sum[0], prop[0], gen[0]);
  CPU_ALU_ant_fa a2(c_ant[0], a[1], b[1], sum[1], prop[1], gen[1]);
  CPU_ALU_ant_fa a3(c_ant[1], a[2], b[2], sum[2], prop[2], gen[2]);
  CPU_ALU_ant_fa a4(c_ant[2], a[3], b[3], sum[3], prop[3], gen[3]);
  CPU_ALU_ant_fa a5(c_ant[3], a[4], b[4], sum[4], prop[4], gen[4]);
  CPU_ALU_ant_fa a6(c_ant[4], a[5], b[5], sum[5], prop[5], gen[5]);
  CPU_ALU_ant_fa a7(c_ant[5], a[6], b[6], sum[6], prop[6], gen[6]);
  CPU_ALU_ant_fa a8(c_ant[6], a[7], b[7], sum[7], prop[7], gen[7]);

  assign {c_out, c_ant} = gen | prop & {c_ant, c_in};
endmodule

module full_adder(input c_in, a, b, output sum, c_out);
  assign sum = a ^ b ^ c_in;
  assign c_out = (a & b) | (c_in & (a ^ b));
endmodule

// a ripple adder
module CPU_SLOW_adder(input c_in, input [7:0] a, b, output [7:0] sum, output c_out);
  wire [6:0] carry;

  full_adder fa1(c_in,     a[0], b[0], sum[0], carry[0]);
  full_adder fa2(carry[0], a[1], b[1], sum[1], carry[1]);
  full_adder fa3(carry[1], a[2], b[2], sum[2], carry[2]);
  full_adder fa3(carry[2], a[3], b[3], sum[3], carry[3]);
  full_adder fa3(carry[3], a[4], b[4], sum[4], carry[4]);
  full_adder fa3(carry[4], a[5], b[5], sum[5], carry[5]);
  full_adder fa3(carry[5], a[6], b[6], sum[6], carry[6]);
  full_adder fa3(carry[6], a[7], b[7], sum[7], c_out);
endmodule

// a carry-select adder
module CPU_LARGE_adder(input c_in, input [15:0] large, input [7:0] small, output [15:0] sum, output c_out);
  wire [7:0] lower_s;
  wire       lower_c;
  CPU_ALU_adder add_lower(c_in, large[7:0], small, lower_s, lower_c);

  wire [7:0] upper_s_0;
  wire [7:0] upper_c_0;
  CPU_SLOW_adder assume_c0(.c_in(1'b0), large[15:8], 8'd0, .sum(upper_s_0), .c_out(upper_c_0));

  wire [7:0] upper_s_1;
  wire [7:0] upper_c_1;
  CPU_SLOW_adder assume_c1(.c_in(1'b1), large[15:8], 8'd0, .sum(upper_s_1), .c_out(upper_c_1));

  assign sum = lower_c ? {upper_s_1, lower_s} : {upper_s_0, lower_s};
  assign c_out = lower_c ? upper_c_1 : uppper_c_0;
endmodule

// 8-bit add,sub,or,and,xor,shr,shl
module CPU_ALU(input [7:0]vx, vy, input [3:0] op, output [7:0]result, output flag, output write_vf);
  reg cin;
  reg [7:0]addx;
  reg [7:0]addy;
  wire [7:0]adds;
  wire addc;
  // this is a case of premature optimization, the 16-bit adders for PC are almost certaintly much much slower
  CPU_ALU_adder add(cin, addx, addy, adds, addc); 

  always @(*) begin
    case (op)
      4'h4: {cin,addx,addy} = {1'b0,  vx,  vy}; // ADD
      4'h5: {cin,addx,addy} = {1'b1,  vx, ~vy}; // SUB x - y
      4'h7: {cin,addx,addy} = {1'b1, ~vx,  vy}; // SUB y - x
      default: {cin,addy} = 9'd0;
    endcase
  end

  always @(*) begin
    case (op)
      4'h0: {out, flag, write_vf} = {vy     , 1'd0 , 1'b0}; // COPY y
      4'h1: {out, flag, write_vf} = {vx | vy, 1'd0 , 1'b0}; // OR
      4'h2: {out, flag, write_vf} = {vx & vy, 1'd0 , 1'b0}; // AND
      4'h3: {out, flag, write_vf} = {vx ^ vy, 1'd0 , 1'b0}; // XOR
      4'h4: {out, flag, write_vf} = {adds   , addc , 1'b1}; // ADD
      4'h5: {out, flag, write_vf} = {adds   , addc , 1'b1}; // SUB x - y (is the carry flag correctly set when borrowing?)
      4'h6: {out, flag, write_vf} = {vx>>1  , vx[0], 1'b1}; // SHR
      4'h7: {out, flag, write_vf} = {adds   , addc , 1'b1}; // SUB y - x (? same as ^^)
      4'hE: {out, flag, write_vf} = {vx<<1  , vx[7], 1'b1}; // SHL
      default: {out, flag, write_vf} = {vx  , 1'd0 , 1'b0}; // COPY x
    endcase
  end
endmodule
