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
    parameter FILTER_LEN = 8,        // ps2_clk glitch filter length (clk cycles)
    parameter TIMEOUT = 17'd100_100
) (
    input wire        clk,       // 100 MHz board clock
    input wire        rst_n,     // active-low synchronous reset which sets all keys to released
    input wire        ps2_clk,   // keyboard clock (10 - 16.7 kHz)
    input wire        ps2_data,  // keyboard data
    output reg [15:0] keeb,      // bit k = 1 while hex key k is held
    output reg [3:0]  keeb_last  // most recently pressed mapped key (0-F), number encoded
);

    // ------------ Synchronizers ------------
    reg [1:0] clk_sync = 2'b11; 
    reg [1:0] data_sync = 2'b11;
    always @(posedge clk) begin
       clk_sync <= {clk_sync[0], ps2_clk};
       data_sync <= {data_sync[0], ps2_data}; 
    end
    wire ps2_clk_s = clk_sync[1];
    wire ps2_data_s = data_sync[1];

    // ------------ Glitch filter on PS/2 clock ------------
    reg [FILTER_LEN-1:0] filt_sr = {FILTER_LEN{1'b1}};
    reg ps2_clk_f = 1'b1;
    reg ps2_clk_f_prev = 1'b1;
    always @(posedge clk) begin 
        
    end
endmodule