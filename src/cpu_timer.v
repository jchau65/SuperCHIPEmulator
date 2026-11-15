module CPU_Timer(
  // value to load in
  wire [7:0]input,
  // on rising edge, if `load` is set, load the counter.
  wire clock,
  // hold high through clock to decrement the timer
  wire decrement,
  // hold high through clock to load the timer with `input`
  wire load,
  // current value
  wire [7:0]value,
  // equiv. to value > 1
  wire active
);
  reg [7:0]timer;

  wire [7:0]inp_next;
  assign inp_next = load ? input : timer;

  wire [7:0]timer_next;
  CPU_SLOW_adder decrementer(
    .c_in(1'b0),
    .a(inp_next), // if load, take input, else take timer
    .b((|inp_next & decrement) ? 8'hF : 8'h0), // only decrement if required, and if decrementing would not saturate
    .sum(timer_next)
  );

  always @(posedge clock) begin
    timer <= timer_next;
  end

  assign value = timer;
  assign active = timer > 8'h1; // Tone will only respond to values greater than x1
endmodule
