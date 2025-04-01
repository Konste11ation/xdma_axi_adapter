`timescale 1ns/1ps

module tb_xdma_stream_arbiter();
    parameter DATA_WIDTH = 32;
    parameter type data_t = logic [DATA_WIDTH-1:0];
    parameter N_INP = 3;
    parameter PKT_LEN = 50;
    parameter TCK = 2ns;
    logic clk_i;
    logic rst_ni;
    initial begin
        rst_ni = 1;
        #20ns;
        rst_ni = 0;
        #20ns;
        rst_ni = 1;
    end
    // Generate reset and clock.
    initial begin
        clk_i = 0;
        #50ns;
        forever begin
            clk_i = 1;
            #(TCK/2);
            clk_i = 0;
            #(TCK/2);
        end
    end

    // DUT interface
    logic                             done_i;
    logic                             busy_o;
    logic                             start_o;
    logic [N_INP-1:0]                 inp_valid_i;
    logic [N_INP-1:0]                 inp_ready_o;
    logic [N_INP-1:0][DATA_WIDTH-1:0] inp_data_i ;
    logic [DATA_WIDTH-1:0]            oup_data_o;
    logic                             oup_valid_o;
    logic                             oup_ready_i;

    // DUT
    xdma_stream_arbiter #(
        .data_t(logic [DATA_WIDTH-1:0]),
        .N_INP(N_INP)
    ) dut (.*);
    // Input fifo
    logic [N_INP-1:0] inp_fifo_pop;
    logic [N_INP-1:0] inp_fifo_empty;
    logic [N_INP-1:0] inp_fifo_push;
    logic [N_INP-1:0] inp_fifo_full;

    logic [DATA_WIDTH-1:0] tb_data [N_INP]; //test data
    logic [N_INP-1:0] tb_data_valid;
    logic [N_INP-1:0] tb_data_ready;
    // The input fifos
    generate
    for (genvar i = 0; i < N_INP; i++) begin : gen_input_fifos
        fifo_v3 #(
            .DEPTH (100),
            .dtype (logic [DATA_WIDTH-1:0])
        ) i_inp_fifo (
            .clk_i      (clk_i),
            .rst_ni     (rst_ni),
            .flush_i    (1'b0),
            .testmode_i (1'b0),
            .full_o     (inp_fifo_full[i]),
            .empty_o    (inp_fifo_empty[i]),
            .usage_o    (),  
            .data_i     (tb_data[i]),        
            .push_i     (inp_fifo_push[i]),  
            .data_o     (inp_data_i[i]),     
            .pop_i      (inp_fifo_pop[i])
        );
        assign inp_fifo_pop[i] = inp_ready_o[i] && !inp_fifo_empty[i];  
        assign inp_valid_i[i]  = !inp_fifo_empty[i];
        assign inp_fifo_push[i] = tb_data_valid[i] && !inp_fifo_full[i];
        assign tb_data_ready[i] = !inp_fifo_full[i];
    end
    endgenerate
    // Output fifo
    logic oup_fifo_full;
    logic oup_fifo_empty;
    logic oup_fifo_push;
    logic oup_fifo_pop;
    logic [DATA_WIDTH-1:0] oup_req_current;
    fifo_v3 #(
        .DEPTH (100),
        .dtype (logic [DATA_WIDTH-1:0])
    ) i_oup_fifo (
        .clk_i       ( clk_i              ),
        .rst_ni      ( rst_ni             ),
        .flush_i     ( 1'b0               ),
        .testmode_i  ( 1'b0               ),
        .full_o      ( oup_fifo_full      ),
        .empty_o     ( oup_fifo_empty     ),
        .usage_o     ( ),
        .data_i      ( oup_data_o         ),
        .push_i      ( oup_fifo_push      ),
        .data_o      ( oup_req_current    ),
        .pop_i       ( oup_fifo_pop       )        
    );
    assign oup_ready_i = !oup_fifo_full;
    assign oup_fifo_push = oup_valid_o & oup_ready_i;
    // 输入数据生成器
    generate
    for (genvar i = 0; i < N_INP; i++) begin : gen_data_source
        initial begin
            automatic int pkt_cnt = PKT_LEN;
            automatic bit [DATA_WIDTH-1:0] base_val = i*1000; 
            automatic bit [DATA_WIDTH-1:0] data;
            automatic int delay;
            // 初始化信号
            tb_data_valid[i] = 1'b0;
            tb_data[i] = '0;       
            wait(rst_ni);
            $display("[INFO] Channel%0d started with base=0x%h", i, base_val);
     
            while (pkt_cnt-- > 0) begin
                // 随机间隔插入
                delay = $urandom_range(1, 5);
                repeat(delay) @(posedge clk_i);

                // 生成带通道标识的数据
                data = base_val + $urandom_range(0, 100);
                tb_data[i] = data;
                tb_data_valid[i] = 1'b1;
                // 等待握手完成
                do begin
                    @(posedge clk_i);
                end while (!(tb_data_valid[i] && tb_data_ready[i]));  // 等待ready
                // 结束当前传输
                tb_data_valid[i] = 1'b0;
                pkt_cnt--;    
            end
            $display("[INFO] Channel%0d finished", i);
        end
    end
    endgenerate

    logic clear_i;
    logic en_i;
    logic [3:0] q_o;
    counter #(
        .WIDTH (4)
    ) i_counter (
        .clk_i       ( clk_i              ),
        .rst_ni      ( rst_ni             ),
        .clear_i     ( clear_i            ),
        .en_i        ( en_i               ),
        .load_i      ( '0                 ),
        .down_i      ( '0                 ),
        .d_i         ( '0                 ),
        .q_o         ( q_o                ),
        .overflow_o  (                    )
    );
    assign en_i = oup_valid_o && oup_ready_i;
    assign clear_i = (q_o==4'd10) ;
    assign done_i = clear_i;
    // 超时保护
    initial begin
        oup_fifo_pop = 1'b0;
        wait(done_i);
        repeat(40) begin
            @(posedge clk_i);
            oup_fifo_pop = 1'b1;
        end
        oup_fifo_pop = 1'b0;
        $finish;
    end    
endmodule