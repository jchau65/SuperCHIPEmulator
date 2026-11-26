module CPU_REG_FILE(
  // values of x and y, where to read from for vx/vy
  input  [3:0] rd_x, rd_y,
  // values of vx/vy/v0
  output [7:0] vx, vy, v0,
  // clock on which writes occur
  input        clock,
  // hold up through clock to write `write_data` to `write_addr`
  input        write,
  // addr to write to
  input  [3:0] write_addr,
  // data to write
  input  [7:0] write_data,
  // hold up through clock to set `VF` to `flag_val`
  input        set_flag,
  input        flag_val,
);
  // 16 8-bit registers V0-VF
  reg [7:0]register[15:0];

  // current registers
  assign vx = register[rd_x];
  assign vy = register[rd_y];

  // write
  // TODO: clean up
  always @(posedge clock) if (write | set_flag) begin
    if (write) begin
      if (write_addr != 4'hF) begin
        register[write_addr] <= write_data;
        if (set_flag)
          register[4'hF] <= {7'd0, flag_val};
      end else begin
        register[write_addr] <= set_flag ? {7'd0, flag_val} : write_data;
      end
    end else if (set_flag) begin
      register[4'hF] <= {7'd0, flag_val};
    end
  end
endmodule
