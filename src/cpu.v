// CPU FSM for the CHIP-8
// http://devernay.free.fr/hacks/chip8/C8TECH10.HTM#0nnn
// https://github.com/mattmikolay/chip-8/wiki/CHIP%E2%80%908-Instruction-Set
module CPU(
  // clocks and timing
  input tick_fsm,      // the FSM advances by one step on rising edge
  input tick_en_instr, // gate for CPU clock. enabled when the current tick should progress the CPU one cycle
  input tick_en_60hz , // gate for the timers. enabled 60 times per second to decrement them
  // peripheral I/O
  input [15:0]keeb,      // keyboard state, one-hot (but more than one can be hot) encoding
  input  [3:0]keeb_last, // last key pressed, number encoding
  input  [7:0]rand,      // random number
  output reg  tone,      // indicate to the audio subsystem that it should play a tone
  // memory
  output [15:0]mem_addr,
  output  [7:0]mem_read_data,
  output  [7:0]mem_write_data,
  output       mem_write_en,
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

  // --- I/O ---
  // is the current key we are checking for pressed
  wire keypress;
  assign keypress = &(8'd1 << register[opcode[8+:4]] & keeb);

  // --- General Vx registers V0-VF ---
  wire [7:0] vx, vy;
  reg      reg_write;
  reg [3:0]reg_waddr;
  reg [7:0]reg_wdata;
  CPU_REG_FILE registers(
    .rd_x(opcode[8+:4]), .vx(vx),
    .rd_y(opcode[4+:4]), .vy(vy),
    .write(reg_write),
    .write_addr(reg_waddr),
    .write_data(reg_wdata)
  );

  // --- Program Counter and Index Register---
  // 12-bit for the typical 4096 bytes of RAM (does long jump even exist?)
  reg [11:0]pc;
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
  wire [7:0]alu_result;
  wire      alu_flag;
  wire      alu_flag_set;
  CPU_ALU alu(
    .vx(vx),
    .vy(vy),
    .op(opcode[0+:4]),
    .result(alu_result),
    .flag(alu_flag),
    .write_vf(alu_flag_set)
  );

  // --- Timers ---
  // Timers. when set to nonzero, they shall count down at a rate of 60Hz
  // WARNING: tm*_load must only be kept high through ONE CYCLE! failing to do this can cause problems

  // input shared between timers, only one can be loaded at a time
  reg [7:0]timer_input;
  // delay timer
  wire tmdelay_val;
  reg tmdelay_load;
  CPU_Timer tmdelay(
    .input(timer_input),
    .clock(tick_fsm),
    .decrement(tick_en_60hz),
    .load(tmdelay_load), // <-- only diff in input between the two timers
    .value(tmdelay_val)
  );
  // sound timer
  reg tmsound_load;
  CPU_Timer tmsound(
    .input(timer_input),
    .clock(tick_fsm),
    .decrement(tick_en_60hz),
    .load(tmsound_load), // <-- only diff in input between the two timers
    .active(tone)
  );

  // --- BCD ENCODER ---
  // as legally required
  wire [3:0]vx_as_bcd[2:0];
  BCD_ENCODER bcd(.input(vx), .output(vx_as_bcd));
  
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

  // STAGE TWO - COMPUTE INSTRUCTION
  // 00EE => RET  S1B|    pp  <= 1   laa <= top lab <= 2     |--------------------------------->S1E
  // 0NNN => IGN     |S1B            laa <= PC  lab <= 2     |--------------------------------->S1E
  // 1NNN => JMP     |S1B            laa <= NNN lab <= 0     |--------------------------------->S1E
  // 2NNN => CALL    |S1B pp  <= 1   laa <= NNN lab <= 0     |--------------------------------->S1E
  // bNNN => JMPO    |S1B            laa <= NNN lab <= V[0]  |--------------------------------->S1E
  // aNNN => LDI     |S1B i   <= NNN laa <= PC  lab <= 2     |--------------------------------->S1E
  // Fx1E => ADI  S1B|               laa <= I   lab <= V[x]  |  I <= las  laa <= PC  lab <= 2  |S1E
  // 
  // 3XKK => SKIPEQ, 4KKK => SKIPNE, 5XY0 SKIPEQ
  // 9XY0 => SKIPNE
  // Ex9E - SKP Vx
  // ExA1 - SKNP Vx
  //              S1B|  <comp<=inp>                          |     laa <= PC  lab <= comp?2:0  |S1E
  // Fx0A - WAITK Vx
  //              S1B|  <comp> Vx<=key laa<=PC  lab<=2   wait|--------------------------------->S1E
  // 
  // 6XKK => LOAD X<=KK
  // 7XKK => ADD X<=X+KK
  //            |S1B  alu <= vxKK aluo <= op                 | vx <= alures laa <= PC lab <= 2 |S1E
  // 8XYO => ALU OPERATION Vx/Vf <= OP Vx Vy
  //            |S1B  alu <= vxvy aluo <= op                 | vx <= alures laa <= PC lab <= 2 |S1E
  // cXKK => RNG Vx<=RAND&KK
  //            |S1B  alu <= RRKK aluo <= &                  | vx <= alures laa <= PC lab <= 2 |S1E
  // 
  // Fx07 - LD Vx, DT
  //            S1B|  vx <= dt laa <= PC lab <= 2            |--------------------------------->S1E
  // Fx15 - LD DT, Vx
  // Fx18 - LD ST, Vx
  //            S1B| tmin<=Vx tmload<=1 laa<=PC lab<=2       |-------------------->tmload <= 0 S1E|
  // 
  // 00E0 => GPU CLEAR
  // x   GPU, clear the screen
  // Dxyn - DRW Vx, Vy, nibble
  // x Display (XOR) n-byte sprite starting at memory location I at (Vx, Vy), set VF if any pixels are erased.
  // 
  // Fx29 - LD F, Vx
  // x Set I = location of sprite for hex digit Vx.
  // Fx33 - LD B, Vx
  // x Store BCD representation of Vx in memory locations I, I+1, and I+2.
  // Fx55 - LD [I], Vx
  // x Store registers V0 through Vx in memory starting at location I.
  // Fx65 - LD Vx, [I]
  // x Read registers V0 through Vx from memory starting at location I.





  
  // -X-- can index Vx
  // --Y- can index Vy
  // ---N can be used for display (as the length of a sprite)
  // --KK can be used as an arithmetic constant
  // -NNN can be used as a 12-bit address

  // i stack can be written at SP+1 (rel. to before cycle)
  //   if (SP != 15) { stack[SP+1] <= PC }
  // i SP can be incremented or decremented
  //   SP <= select (opcode) { SP, SP + 1, SP - 1 }
  // i PC can be set to stack[SP], NNN, NNN+V0, or be incremented by 4 (skip) or 2 (next)
  //   ADD_A <= select (opcode) { stack[SP], PC, NNN }, ADD_B <= select (opcode) { 4, 2, 0, V0 } // not exactly implemented like this...
  //   PC <= ADD_SUM

  // x 1 << Vx & KB (with a dependent skip next instruction, either is pressed or is not pressed)
  //   keypress <= AND(onehot(Vx) & KB)
  //   PC_NEXT_FLAGS <= select (keypress, opcode) { PC+4, PC+2 }

  // x Vx can be loaded with the value of the key that was just pressed (need to be able to diff the keyboard)
  //   is_pressed <= OR(latest_keydown_since_last_cycle)
  //   V[x] <= onehot_to_mbw(latest_keydown_...); PC_NEXT_FLAGS <= select (is_pressed) { PC+2, PC+0 }

  // x Vx and Vy can have an arithmetic operation performed, with Vx, Vy, and KK as possible inputs
  //   ALU_A <= V[x], ALU_B = select (opcode) { V[y], KK }
  //   V[x] <= ALU_OUT
  // x KK can be AND'd with a random number and stored in Vx
  //   V[x] = RAND & KK (can dedicate an AND to this to make it single-cycle instead of using the ALU)
  // x Vf can be set to carry (add), NOT borrow (sub), Vx[0]/Vx[7] (shr/shl) or collide (draw)
  //   ... hold for operation to finish
  //   V<f> = select (opcode) { ALU_FLAG, GPU_FLAG }
  // x Vx can be loaded with the value of the delay timer
  //   V[x] <= DELAY
  // x DT and ST can be loaded with Vx
  //   select (opcode) { DT, ST } <= V[x]
  // x I can be loaded with NNN, incremented by Vx, or set to the location of the sprite for Vx. 
  //   increment = I + V[x]; sprite = lookup(V[x])
  //   I <= select (opcode) { I, NNN, increment, sprite }
  // x BCD encoded Vx can be placed at I+:3
  //   bcd = BCD(V[x])
  //   max = 2
  //   index = I
  //   .. shared with next instr
  // x registers V0..Vx can be written or read from memory at I
  //   max = min(V[x], 15)
  //   index = I
  //   LOOP (one clock per)
  //     index <= index + 1
  //     .. TBD (maybe use I as the register and increment then decrement on the last cycle?)

  // a BCD encoder of Vx needs to be available, the 3-byte output of which can be indexed

  // One byte can be written or read from ram at a time

  // GPU interface
  // - clear the screen (instruction side-effect)
  // - draw a sprite
  //    - effect of possibly setting Vf
  
  // 00E0 =>
  // x   GPU, clear the screen
  // 00EE =>
  // x    read stack @ SP into PC and [decrement SP]
  // 0NNN => (old equivalent to 2NNN, ignored by modern interpreters)
  // 1NNN =>
  // x    set PC to NNN
  // 2NNN =>
  // x    [increment SP] and write PC to stack @ SP
  // x    read NNN into PC
  // 3XKK =>
  // x    if Vx == KK,
  // x        increment PC by 2
  // 4XKK =>
  // x    if Vx != KK,
  // x        increment PC by 2
  // 5XY0 =>
  // x    if Vx == Vy,
  // x        increment PC by 2
  // 6XKK =>
  // x   write KK to Vx
  // 7XKK =>
  // x   add KK to Vx and store the result in Vx
  // 8XY0 =>
  // x   write Vy to Vx
  // 8XY1 =>
  // x   write Vx | Vy to Vx
  // 8XY2 =>
  // x   write Vx & Vy to Vx
  // 8XY3 =>
  // x   write Vx ^ Vy to Vx
  // 8XY4 =>
  // x   write Vx + Vy to Vx, set Vf = carry
  // 8XY5 =>
  // x   write Vx - Vy to Vx, set Vf = NOT borrow
  // 8XY6 =>
  // x   write write Vx[0] to Vf
  // x   write Vx >> 1 to Vx, 
  // 8XY7 =>
  // x   write Vy - Vx to Vx, set Vf = NOT borrow
  // 8XYE =>
  // x   write write Vx[7] to Vf
  // x   write Vx << 1 to Vx, 
  // 9XY0 =>
  // x   if Vx != Vy,
  // x       increment PC by 2
  // aNNN =>
  // x   set I to NNN
  // bNNN =>
  // x   add NNN and V0
  // x    set PC to the result
  // cXKK =>
  // x   generate a random number
  // x   AND it with KK, store in Vx
  // Dxyn - DRW Vx, Vy, nibble
  // x Display (XOR) n-byte sprite starting at memory location I at (Vx, Vy), set VF if any pixels are erased.
  // Ex9E - SKP Vx
  // x Skip next instruction if key with the value of Vx is pressed.
  // ExA1 - SKNP Vx
  // x Skip next instruction if key with the value of Vx is not pressed.
  // Fx07 - LD Vx, DT
  // x Set Vx = delay timer value.
  // Fx0A - LD Vx, K
  // x Wait for a key press, store the value of the key in Vx.
  // Fx15 - LD DT, Vx
  // x Set delay timer = Vx.
  // Fx18 - LD ST, Vx
  // x Set sound timer = Vx.
  // Fx1E - ADD I, Vx
  // x Set I = I + Vx.
  // Fx29 - LD F, Vx
  // x Set I = location of sprite for digit Vx.
  // Fx33 - LD B, Vx
  // x Store BCD representation of Vx in memory locations I, I+1, and I+2.
  // Fx55 - LD [I], Vx
  // x Store registers V0 through Vx in memory starting at location I.
  // Fx65 - LD Vx, [I]
  // x Read registers V0 through Vx from memory starting at location I.
endmodule
