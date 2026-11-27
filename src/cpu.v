// CPU FSM for the CHIP-8
// http://devernay.free.fr/hacks/chip8/C8TECH10.HTM#0nnn
// https://github.com/mattmikolay/chip-8/wiki/CHIP%E2%80%908-Instruction-Set
module CPU(
  // clocks and timing
  input        tick_fsm,      // the FSM advances by one step on rising edge
  input        tick_en_instr, // gate for CPU clock. enabled when the current tick should progress the CPU one cycle
  input        tick_en_60hz , // gate for the timers. enabled 60 times per second to decrement them
  // peripheral I/O
  input [15:0] keeb,      // keyboard state, one-hot (but more than one can be hot) encoding
  input  [3:0] keeb_last, // last key pressed, number encoding
  input  [7:0] rand,      // random number
  output reg   tone,      // indicate to the audio subsystem that it should play a tone
  // memory
  output [15:0] mem_addr,
  output  [7:0] mem_read_data,
  output  [7:0] mem_write_data,
  output        mem_write_en,
  // --- GFX ---
  // High for one cycle to start a command; all the graphics outputs below must already hold the right values. Only sent when ‘gfx_busy’ is 0.
  output reg gfx_start,
  // Picks the command for the graphics
  // 0 → CLEAR
  // XO-CHIP also clears the screen when switching between lo-res and hi-res.
  // 1 → DRAW
  // 2 → SCROLL DOWN
  // 3 → SCROLL RIGHT
  // 4 → SCROLL LEFT
  // 5 → SCROLL UP (XO-CHIP only)
  output [2:0] gfx_cmd,
  // Value of VX/VY label: which is where the sprite’s left edge goes
  output [7:0] gfx_x, gfx_y,
  // For DRAW: dictates how many rows tall the sprite is (1-15; 0 means a 16x16 sprite, 1-15 means N rows and 8 wide). This is how the original CHIP-8 sprite works
  // SUPER CHIP does 8x16 in lo-res mode when gfx_n is 0
  // For SCROLL DOWN/UP: dictates how many rows to scroll
  output [3:0] gfx_n,
  // Value of I: the memory address of the sprite’s first byte. 16 bits for XO-CHIP
  output [15:0] gfx_i,
  // Dictates which color layer(s) a command affects. Bit 0 = plane 1, bit 1 = plane 2.
  // SUPER-CHIP uses 1 plane, always 2’b01
  // XO-CHIP uses twice as many sprite bytes if both bits are set
  output reg [1:0] gfx_plane,
  // Dictates the current screen mode: 1 = 128 x 64, 0 = 64 x 32
  output reg hires,
  // After a DRAW, 1 if the spire turned off any pixel that was already on, else 0. The CPU copies it into VF so the game can detect hits
  input gfx_collision,
  // --- Audio! ---
  // How fast the sound pattern plays, which dictates the pitch. The rate is 4000 x 2^((pitch - 64)/48) bits per second, so 64 = 4000 bits per second.
  output reg [7:0] audio_pitch,
// A 128-bit (16 bytes) waveform that the audio module plays one bit at a time while tone is 1.
output reg [7:0]audio_pattern[15:0],
  // --- Debug Interface ---
  // The program counter. We can show this on the 7-segment display so we can see where the game is
  output [15:0] dbg_pc,
  // The instruction currently running, also can be shown on the 7-segment display for debugging purposes.
  output [15:0] dbg_opcode,
  // 1 after exiting. Forces the CPU to stop until reset.
  output reg halted,
  // Outputs a 1 if the CPU fetches a non-usable instruction. Forces the CPu to halt so the program counter and the opcode remain on the display, making debugging easier.
  output reg bad_opcode; // ❗ even if this is partially implemented, it wont catch everything and some invalid inputs will cause UB
);
  // --- RAM addressing ---
  // 0000-01FF: allocated for the "emulator". we shall use this for storing useful things
  //            >>000-0AF: <unallocated>
  //            >>0AF-0FF: the default font
  //            >>000-1FF: <unallocated> (previously was going to be the stack, but no.)
  // 0200-0FFF: available to the program. the final 352 bytes of ram are reserved for
  //          "variables and display refresh". we ignore this.

  // --- EXTENDED MEMORY ---
  // 1000-FFFF: specified by the XO- extensions, this region is accessed by special instructions
  //            this region is *not* executable

  // --- General Vx registers V0-VF ---
  wire [7:0] vx, vy, v0; // used by opcodes generally
  reg       reg_wclock; // rising edge
  wire      reg_write; // hold through clock to write reg_waddr
  wire [3:0]reg_waddr;
  wire [7:0]reg_wdata;
  wire      reg_flag_set; // hold through clock to set VF
  wire      reg_flag_val;
  CPU_REG_FILE registers(
    .rd_x(opcode[8+:4]), .vx(vx),
    .rd_y(opcode[4+:4]), .vy(vy), .v0(v0),
    .clock(reg_wclock),
    .write(reg_write), .write_addr(reg_waddr), .write_data(reg_wdata),
    .set_flag(reg_flag_set), .flag_val(reg_flag_val),
  );

  // 6XKK => LOAD X<=KK
  // 7XKK => ADD X<=X+KK
  // 8XYO => ALU OPERATION Vx/Vf <= OP Vx Vy
  // cXKK => RNG Vx<=RAND&KK
  //            |S1B  <cfg ALU> || write <= 1 waddr <= x wdata <= res rfs <= aluwf rfv <= aluf | rclk <= 1 laa <= PC lab <= 2 |S1E
  // 
  // Fx07 - LD Vx, DT
  //            |S1B  <cfg reg>                                                                | rclk <= 1 laa <= PC lab <= 2  |S1E
  always @(*) casez (opcode)
    16'h6???, 16'h7???, 16'h8???, 16'hC???: begin
      reg_write <= 1'b1; reg_waddr <= opcode[8+:4]; reg_wdata <=  alu_result; reg_flag_set <= alu_flag_set; reg_flag_val <= alu_flag; end
    16'hF?07: begin
      reg_write <= 1'b1; reg_waddr <= opcode[8+:4]; reg_wdata <= tmdelay_val; reg_flag_set <= 1'b0;         reg_flag_val <= 1'b0;     end
    default: begin
      reg_write <= 1'b0; reg_waddr <= 4'd0;         reg_wdata <= 8'd0;        reg_flag_set <= 1'b0;         reg_flag_val <= 1'b0;     end
  endcase


  // --- Program Counter and Index Register---
  // 12-bit for the typical 4096 bytes of RAM (does long jump even exist?)
  // NOTE: missing one bit because that bit is always zero 
  reg [11:1]pc;
  reg [15:0] i;

  reg  [15:0]spec_add_16b;
  reg  [7:0]  spec_add_8b;
  wire [15:0]spec_add_sum;
  CPU_LARGE_adder spec_add(
    .c_in(1'b0),
    .large(spec_add_16b),
    .small(spec_add_8b),
    .sum(spec_add_sum)
  );

  // --- THE STACK ---
  reg         stack_pp;
  wire [11:0] stack_top;
  CPU_STACK_ENGINE stack(
    .do_pp(stack_pp),
    .direction(~&(opcode[12+:4] ^ 4'h2)), // check for PUSH instruction
    .new_val(pc),
    .top_val(stack_top)
  );

  // --- ALU ---
  // 6XKK => LOAD X<=KK
  // 7XKK => ADD X<=X+KK
  //            |S1B  alu <= vxKK aluo <= op || <cfg reg> | rclk <= 1 laa <= PC lab <= 2 |S1E
  // 8XYO => ALU OPERATION Vx/Vf <= OP Vx Vy
  //            |S1B  alu <= vxvy aluo <= op || <cfg reg> | rclk <= 1 laa <= PC lab <= 2 |S1E
  // cXKK => RNG Vx<=RAND&KK
  //            |S1B  alu <= RRKK aluo <= &  || <cfg reg> | rclk <= 1 laa <= PC lab <= 2 |S1E
  wire [7:0]alu_x;
  wire [7:0]alu_y;
  wire [3:0]alu_op;
  always @(*)
    casez (opcode)
      16'h6xxx: {alu_x, alu_y, alu_op} <= {vx,   kk, 4'h0}; // COPY   KK
      16'h7xxx: {alu_x, alu_y, alu_op} <= {vx,   kk, 4'h4}; // ADD VX+KK
      16'h8xxx: {alu_x, alu_y, alu_op} <= {vx,   vy, opcode[0+:4]}; // OP VX VY
      16'hCxxx: {alu_x, alu_y, alu_op} <= {rand, kk, 4'h2}; // AND RAND&KK
      default:  {alu_x, alu_y, alu_op} <= 16'd0;
    endcase
  wire [7:0]alu_result;
  wire      alu_flag;
  wire      alu_flag_set;
  CPU_ALU alu(
    .vx(alu_x),
    .vy(alu_y),
    .op(alu_op),
    .result(alu_result),
    .flag(alu_flag),
    .write_vf(alu_flag_set)
  );

  // --- Timers ---
  // Timers. when set to nonzero, they shall count down at a rate of 60Hz
  // WARNING: tm*_load must only be kept high through ONE CYCLE! failing to do this can cause problems

  // delay timer
  wire tmdelay_val;
  reg tmdelay_load;
  CPU_Timer tmdelay(
    .input(vx),
    .clock(tick_fsm),
    .decrement(tick_en_60hz),
    .load(tmdelay_load), // <-- only diff in input between the two timers
    .value(tmdelay_val)
  );
  // sound timer
  reg tmsound_load;
  CPU_Timer tmsound(
    .input(vx),
    .clock(tick_fsm),
    .decrement(tick_en_60hz),
    .load(tmsound_load), // <-- only diff in input between the two timers
    .active(tone)
  );

  // --- BCD ENCODER ---
  // as legally required
  wire [3:0]vx_as_bcd[2:0];
  BCD_ENCODER bcd(.input(vx), .output(vx_as_bcd));

  // --- STATE ---
  reg [5:0]state;
  // set to 1 when the next "opcode" read in is actually a 2-byte argument for the previous instruction
  // used only by XO-CHIP F000 load long
  reg fetch_large_argument;
  reg [15:0]opcode;

  wire [11:0] nnn;
  assign nnn = opcode[0+:12];
  wire [11:0] kk;
  assign nnn = opcode[0+:8];

  // --- For Comparator Opcodes ---
  // is the current key we are checking for pressed
  wire keypress;
  assign keypress = &(8'd1 << vx & keeb);

  // store the result of comparisons that happen in opcodes
  wire comparator; 

  always @(*)
    casez (opcode)
      16'h3xxx: comparator <= vx == kk; // SKIPEQ
      16'h4xxx: comparator <= vx != kk; // SKIPNE
      16'h5xxx: comparator <= vx == vy; // SKIPEQ
      16'h9xxx: comparator <= vx != vy; // SKIPNE
      16'hFx0A: comparator <= {4'b0000, keeb_last} == vx; // WAITK Vx
      default:  comparator <= 1'b0;
    endcase

  // --- Debug Interface ---
  assign dbg_pc = pc;
  assign dbg_opcode = opcode;

  // --- Graphics ---
  wire [15:0]char_addr;
  CPU_CHAR_ADDR_LUT lu1(.hex_char(vx), .hires(opcode === 16'hFx30), .address(char_addr));
  assign gfx_i = i;
  assign gfx_x = vx;
  assign gfx_y = vy;

  always @(*)
    casez (opcode)
      // 00E0 => GPU CLEAR
      16'h00E0: begin gfx_cmd <= 3'd0; gfx_n <= 3'd4;         end // gfx_n = 4 is not important, but hopefully minimizes synthesis complexity
      // DXYN*    Show N-byte sprite from M(I) at coords (VX,VY), VF := collision. If N=0 and extended mode, show 16x16 sprite.
      16'hDxxx: begin gfx_cmd <= 3'd1; gfx_n <= opcode[0+:4]; end
      // 00CN*    Scroll display N lines down
      16'h00Cx: begin gfx_cmd <= 3'd2; gfx_n <= opcode[0+:4]; end
      // 00FB*    Scroll display 4 pixels right
      16'h00FB: begin gfx_cmd <= 3'd3; gfx_n <= 3'd4;         end
      // 00FC*    Scroll display 4 pixels left
      16'h00FC: begin gfx_cmd <= 3'd4; gfx_n <= 3'd4;         end
      // scroll-up n (0x00DN) scroll the contents of the display up by 0-15 pixels.
      16'h00Dx: begin gfx_cmd <= 3'd5; gfx_n <= opcode[0+:4]; end
      default:  begin gfx_cmd <= 4'd0; gfx_n <= 3'd4;         end
    endcase

  // --- States ---
  localparam SPRESET       = 6'b000000; // reset? or something?
  // -- GATED ON tick_en_instr --
  localparam SREADHI       = 6'b000001; // read opcode high byte
  // S1B
  localparam SREADLO       = 6'b000010; // read opcode low byte
  // scomp* compute states
  localparam SCOMP_START   = 6'b000100;
  localparam SCOMP_ESETI   = 6'b001100; // for I <= NNN + Vx we need to use spec_adder twice, which takes an extra cycle
  localparam SCOMP_GFXWAIT = 6'b010100; // wait for gfx_busy to be zero
  // S1E
  localparam SSETPC        = 6'h000011; // update PC value

  // STAGE ONE - FETCH INSTRUCTION
  // - read 2 bytes @ PC from ram -> `opcode`
  // bytes in ram are ->>> HILO so we read HI of opcode and then LO
  // 
  // S1E (after end of normal cycle)
  // addr bus <- PC
  // operation <- read
  // ---
  // opcode[4+:4] <- data bus
  // addr bus <- PC+1
  // ---
  // opcode[0+:4] <- data bus
  // S1B (before begin of normal cycle, only lower bits of opcode are determined)
  // Named States -- S1L | S1B | S2X | S2Y | S1E -> (loop) 

  always @(posedge tick_fsm) if (~halted) begin
    casez (state)
      SPRESET: begin
        // TODO
      end
      SREADHI: if (tick_en_instr) begin
        opcode[8+:8] <= mem_read_data;
        mem_addr <= {4'd0, pc, 1'b1}; // read the second (lower) byte
        state <= SREADLO;
      end
      SREADLO: begin
        opcode[0+:8] <= mem_read_data;
        // -- S1B --
        if (fetch_large_argument) begin
          // phase II of 0xF000 `LDI long`
          i <= fetch_large_argument;
          spec_add_16b <= pc;
          spec_add_8b <= 8'd2;
          state <= SSETPC;
        end else begin
          // normal begin instruction
          state <= SCOMP_START;
        end
      end
      SCOMP_START: begin
        casez (opcode)
          // 00EE => RET  S1B| pp  <= 1   laa <= top lab <= 2     |--------------------------------->S1E
          16'h00EE: begin stack_pp <= 1; spec_add_16b <= stack_top; spec_add_8b <= 8'd2; state <= SSETPC; end
          // 0NNN => IGN  S1B|            laa <= PC  lab <= 2     |--------------------------------->S1E
          // IGNORED (call machine language instruction doesn't even make sense... this isn't an emulator!)
          // 16'h0xxx: NOT IMPLEMENTED because some SCHIP/XO-CHIP instructions use this!
          // 1NNN => JMP  S1B|            laa <= NNN lab <= 0     |--------------------------------->S1E
          16'h1xxx: begin                spec_add_16b <= stack_top; spec_add_8b <= 8'd0; state <= SSETPC; end
          // 2NNN => CALL S1B| pp  <= 1   laa <= NNN lab <= 0     |--------------------------------->S1E
          16'h2xxx: begin stack_pp <= 1; spec_add_16b <= nnn;       spec_add_8b <= 8'd0; state <= SSETPC; end
          // aNNN => LDI  S1B| i   <= NNN laa <= PC  lab <= 2     |--------------------------------->S1E
          16'hAxxx: begin i <= nnn       spec_add_16b <= pc;        spec_add_8b <= 8'd2; state <= SSETPC; end
          // bNNN => JMPO S1B|            laa <= NNN lab <= V[0]  |--------------------------------->S1E
          16'hBxxx: begin                spec_add_16b <= nnn;       spec_add_8b <= v0;   state <= SSETPC; end
          // Fx1E => ADI  S1B|            laa <= I   lab <= V[x]  |  I <= las  laa <= PC  lab <= 2  |S1E
          16'hFx1E: begin                spec_add_16b <= i;         spec_add_8b <= vx;   state <= SCOMP_ESETI; end

          // i := long NNNN (0xF000, 0xNNNN) load i with a 16-bit address.
          16'hF000: begin
           fetch_large_argument <= 1'b1; spec_add_16b <= pc;        spec_add_8b <= 8'd2; state <= SSETPC; end

          // 3XKK => SKIPEQ, 4KKK => SKIPNE, 5XY0 SKIPEQ
          // 9XY0 => SKIPNE
          // Ex9E - SKP Vx
          // ExA1 - SKNP Vx
          //              S1B| laa <= PC  lab <= comp?4:2  |S1E
          16'h3xxx, 16'h4xxx, 16'h5xxx, 16'h9xxx, 16'hEx9E, 16'hExA1: begin
                          spec_add_16b <= pc; spec_add_8b <= comparator ? 8'd4 : 8'd2; state <= SSETPC; end
          // Fx0A - WAITK Vx
          //              S1B| laa <= PC  lab <= keyp?2:0  |S1E
          16'hFx0A: begin spec_add_16b <= pc; spec_add_8b <=   keypress ? 8'd2 : 8'd0; state <= SSETPC; end

          // 6XKK => LOAD X<=KK
          // 7XKK => ADD X<=X+KK
          //            |S1B  alu <= vxKK aluo <= op || write <= 1 waddr <= x wdata <= res rfs <= aluwf rfv <= aluf | rclk <= 1 laa <= PC lab <= 2 |S1E
          // 8XYO => ALU OPERATION Vx/Vf <= OP Vx Vy
          //            |S1B  alu <= vxvy aluo <= op || write <= 1 waddr <= x wdata <= res rfs <= aluwf rfv <= aluf | rclk <= 1 laa <= PC lab <= 2 |S1E
          // cXKK => RNG Vx<=RAND&KK
          //            |S1B  alu <= RRKK aluo <= &  || write <= 1 waddr <= x wdata <= res rfs <= aluwf rfv <= aluf | rclk <= 1 laa <= PC lab <= 2 |S1E
          // 
          // Fx07 - LD Vx, DT
          //            |S1B  <cfg reg>                                                                             | rclk <= 1 laa <= PC lab <= 2 |S1E
          16'h6xxx, 16'h7xxx, 16'h8xxx, 16'hCxxx, 16'hFx07: begin
            reg_wclock <= 1; spec_add_16b <= pc; spec_add_8b <= 8'd2; state <= SSETPC; end

          // Fx15 - LD DT, Vx
          // Fx18 - LD ST, Vx
          //            S1B| tmin<=Vx tmload<=1 laa<=PC lab<=2       |-------------------->tmload <= 0 S1E|
          16'hFx15, 16'hFx18: begin tmdelay_load <= 1'b1; spec_add_16b <= pc; spec_add_8b <= 8'd2; state <= SSETPC; end
          // pitch := vx (0xFX3A) set the audio pattern playback rate to 4000*2^((vx-64)/48)Hz.
          16'hFx3A:           begin audio_pitch  <= vx;   spec_add_16b <= pc; spec_add_8b <= 8'd2; state <= SSETPC; end

          // plane n (0xFN01) select zero or more drawing planes by bitmask (0 <= n <= 3).
          16'hFx01: begin gfx_plane <= opcode[8+:4];      spec_add_16b <= pc; spec_add_8b <= 8'd2; state <= SSETPC; end
          // 00FE*    Disable extended screen mode
          // 00FF*    Enable extended screen mode for full-screen graphics
          16'h00FE, 16'h00FF: begin hires <= opcode[0];   spec_add_16b <= pc; spec_add_8b <= 8'd2; state <= SSETPC; end

          // 00E0 => GPU CLEAR
          // 00CN*    Scroll display N lines down
          // 00FB*    Scroll display 4 pixels right
          // 00FC*    Scroll display 4 pixels left
          // scroll-up n (0x00DN) scroll the contents of the display up by 0-15 pixels.
          // DXYN*    Show N-byte sprite from M(I) at coords (VX,VY), VF := collision. If N=0 and extended mode, show 16x16 sprite.
          16'h00E0, 16'h00Cx, 16'h00FB, 16'h00FC, 16'h00Dx: begin gfx_start <= 1'b1; state <= SCOMP_GFXWAIT; end

          // Fx29 - LD F, Vx
          // x Set I = location of **5-byte** sprite for hex digit Vx.
          // FX30*    Point I to **10-byte** font sprite for digit VX (0..9)
          16'hFx29, 16'hFx30: begin i <= char_addr; spec_add_16b <= pc; spec_add_8b <= 8'd2; state <= SSETPC; end

          // Fx33 - LD B, Vx
          // x Store BCD representation of Vx in memory locations I, I+1, and I+2.

          // Fx55 - LD [I], Vx
          // x Store registers V0 through Vx in memory starting at location I.
          // Fx65 - LD Vx, [I]
          // x Read registers V0 through Vx from memory starting at location I.

          // save vx - vy (0x5XY2) save an inclusive range of registers to memory starting at i. (ORDER CAN BE DECENDING OR ASCENDING!)
          // load vx - vy (0x5XY3) load an inclusive range of registers from memory starting at i. (ORDER CAN BE DESCENDING OR ASCENDING!)

          // FX75*    Store V0..VX in RPL user flags (X <= 7)
          // FX85*    Read V0..VX from RPL user flags (X <= 7) 

          // saveflags vx (0xFN75) save v0-vn to flag registers. (generalizing SCHIP).
          // loadflags vx (0xFN85) restore v0-vn from flag registers. (generalizing SCHIP).

          // audio (0xF002) store 16 bytes starting at i in the audio pattern buffer.
                    
          // 00FD*    Exit CHIP interpreter
          16'h00FD: begin halted <= 1'b1; end
          
          // report errors / invalid instructions
          default : begin halted <= 1'b1; bad_opcode <= 1'b1; end;
        endcase
      end
      SCOMP_ESETI: begin
        // Fx1E => ADI  S1B|            laa <= I   lab <= V[x]  |  I <= las  laa <= PC  lab <= 2  |S1E
        i <= spec_add_sum;
        spec_add_16b <= pc;
        spec_add_8b <= 8'd2;
        state <= SSETPC;
      end
      SCOMP_GFXWAIT: if (~gfx_busy) begin
        spec_add_16b <= pc;
        spec_add_8b <= 8'd2;
        state <= SSETPC;
      end
      SSETPC: begin
        // -- S1E --
        tmdelay_load <= 1'b0; // stop loading timers
        tmsound_load <= 1'b0;
        stack_pp <= 1'b0; // end stack operation
        reg_wclock <= 1'b0; // end reg write
        gfx_start <= 1'b0; // end gfx op
        // -- normal SSETPC content --
        // update PC
        pc <= spec_add_sum[11:1];
        // put it on the bus
        mem_addr <= {4'd0, spec_add_sum[11:1], 1'b0}; // technically we could wire the last bit and it SHOULD work, but that's more liable to UB
        mem_write_en <= false; // read!
        // next state
        state <= SREADHI;
      end
      default;
    endcase
  end
endmodule
