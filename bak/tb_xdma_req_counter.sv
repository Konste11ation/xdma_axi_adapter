`timescale 1ns/1ps

module tb_xdma_req_counter();

parameter LenWidth = 16;
typedef logic [LenWidth-1:0] len_t;

// Clock and Reset
logic clk_i;
logic rst_ni;

// DUT I/O
len_t trans_len_i;
logic busy_i;
logic axi_w_valid;
logic axi_w_ready;
logic trans_complete_o;

// Instantiate DUT
xdma_req_counter #(
    .LenWidth(LenWidth),
    .len_t(len_t)
) dut (
    .clk_i,
    .rst_ni,
    .trans_len_i,
    .busy_i,
    .axi_w_valid,
    .axi_w_ready,
    .trans_complete_o
);

// Clock generation
initial begin
    clk_i = 0;
    #50ns;
    forever #2 clk_i = ~clk_i;
end

// Reset initialization
initial begin
    rst_ni = 1;
    #10ns;
    rst_ni = 0;
    #10ns;
    rst_ni = 1;
end

// Test scenario
initial begin
    // ... initialization ...

    // Test Case 1: Single transfer with protocol check
    $display("[TEST1] AXI compliant transfer");
    axi_handshake(4); // Transfer length = 4
    $finish;
end


// AXI W channel handshake controller (AXI compliant)
task automatic axi_handshake(int length);
    // Initialize signals
    int delay;
    busy_i = 0;
    trans_len_i = 0;
    axi_w_valid = 0;
    axi_w_ready = 0;
    
    // Start transaction
    @(posedge clk_i);
    busy_i = 1;
    trans_len_i = length;
    @(posedge clk_i);
    axi_w_valid = 1;
    for (int i  = 0; i<length; i++) begin
        delay = $urandom_range(0,5);
        repeat(delay) @(posedge clk_i);
        axi_w_ready = 1;
        @(posedge clk_i);
        axi_w_ready = 0;
    end
    
endtask



endmodule