// Font Lookup Tables

module CPU_CHAR_ADDR_LUT(
  input   [7:0]hex_char,
  input        hires,
  output [15:0]address,
);
  wire [15:0]map_5b[15:0];
  assign map_5b = { 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000 };

  // note that this should be ZERO for addrs > 9
  // (hex letters not supported for high-res mode)
  wire [15:0]map_10b[15:0];
  assign map_10b = { 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000 };

  assign address = hires ? map_10b[hex_char] : map_5b[hex_char];
endmodule
