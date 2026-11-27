// General documentation to be added later to the main google doc

// PS/2 keyboard -> 16-key CHIP-8 hex keypad

// Artix-7 FPGA's port goes through an on-board USB HID host
// that emulates a PS/2 keyboard on PS2_CLK / PS2_DATA.

// Key layout (standard CHIP-8 mapping):
//      Keyboard        CHIP-8
//      1 2 3 4    ->   1 2 3 C
//      Q W E R    ->   4 5 6 D
//      A S D F    ->   7 8 9 E
//      Z X C V    ->   A 0 B F

`timescale 1ns / 1ps

module ps2_keypad #(

) (
    input wire clk,
    input wire rst_n,
    input wire ps2_clk,
    input wire ps2_data,
    output reg [15:0] keeb,
    output reg [3:0] keeb_last,
)
endmodule