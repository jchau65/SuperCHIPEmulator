module CPU_REG_FILE(
  // values of x and y, where to read from for vx/vy
  input  [3:0] rd_x, rd_y,
  // values of vx/vy
  output [7:0] vx, vy,
  // on posedge, write `write_data` to `write_addr`
  input        write,
  // addr to write to
  input  [3:0] write_addr,
  // data to write
  input  [7:0] write_data
);
  // 16 8-bit registers V0-VF
  reg [7:0]register[15:0];

  // current registers
  assign vx = register[rd_x];
  assign vy = register[rd_y];

  // write
  always @(posedge write) begin
    register[write_addr] <= write_data;
  end
endmodule
