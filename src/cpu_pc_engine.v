module CPU_PC_ENGINE(
  // on rising edge, either push or pop the stack
  input skip, 
  // 1 = push, 0 = pop
  input         direction,
  // new value to put on top of the stack
  input  [11:0] new_val, 
  // current value on top of the stack
  output [11:0] top_val, 
);
  // - the stack: 192-bit stack, or 16 calls. 12 is required for CHIP-8 but "modern emulators may wish to allow for more" (great)
  reg [11:0]stack[15:0];
  // stack pointer, 4-bits equiv 16 calls, or xFF bytes of stack usage 
  reg  [3:0]sp;
  wire [3:0]sp_next; // sp +/- direction
  assign sp_next = direction ? stack + 1 : stack - 1;
  assign top_val = stack[sp];

  always @(posedge do_pp) begin
    sp <= sp_next;
    // for push this works as intended, for pop, it performs a write that never will be seen!
    // no branching or gating is needed
    stack[sp] <= new_val;
  end
endmodule

