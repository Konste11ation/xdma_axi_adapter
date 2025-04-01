// Fanchen Kong <fanchen.kong@kuleuven.be>
// Yunhao Deng <yunhao.deng@kuleuven.be>

module xdma_data_mover #(
    /// Data width of the AXI bus
    parameter int unsigned DataWidth    = -1,
    /// Number of AW beats that can be in-flight
    parameter int unsigned ReqFifoDepth = -1,
    /// AXI4+ATOP request struct definition.
    parameter type         axi_req_t    = logic,
    /// AXI4+ATOP response struct definition.
    parameter type         axi_res_t    = logic,
    /// aw descriptor
    /// - `id`: AXI id
    /// - `address`: address of burst
    /// - `length`: burst length
    /// - `size`: bytes in each burst
    /// - `burst`: burst type; only INC supported
    /// - `cache`: cache type
    parameter type         desc_aw_t    = logic,
    /// w descriptor
    /// - `num_beats`: number of beats in the burst
    /// - `is_single`: burst length is 0
    /// - `is_write_data`: need handshake when we try to write data
    parameter type         desc_w_t     = logic,
    /// Write request definition. Includes:
    /// - aw descriptor
    ///  - `id`: AXI id
    ///  - `last`: last transaction in burst
    ///  - `address`: address of burst
    ///  - `length`: burst length
    ///  - `size`: bytes in each burst
    /// - w descriptor
    ///  - `num_beats`: number of beats in the burst
    ///  - `is_single`: burst length is 0
    ///  - `is_write_data`: need handshake when we try to write data
    /// - transfer descriptor
    ///  - `total_len`: total length of this transfer
    parameter type         write_req_t  = logic,
    // DO NOT OVERWRITE THIS PARAMETER
    parameter type data_t = logic [DataWidth-1:0],
    parameter type strb_t = logic [(DataWidth/8)-1:0],
) (
    /// Clock
    input  logic       clk_i,
    /// Asynchronous reset, active low
    input  logic       rst_ni,
    /// AXI4+ATOP master request
    output axi_req_t   axi_dma_req_o,
    /// AXI4+ATOP master response
    input  axi_res_t   axi_dma_res_i,
    /// Write transfer request
    input  write_req_t write_req_i,
    /// Handshake: write transfer request valid
    input  logic       w_valid_i,
    /// Handshake: write transfer request ready
    output logic       w_ready_o,
    /// Input data
    input  data_t      data_i,
    input  logic       data_valid_i,
    output logic       data_ready_o,
    /// Input grant
    input  logic       grant_i,
    /// Event: a transaction has completed
    output logic       trans_complete_o
);

    //--------------------------------------
    // AW emitter
    //--------------------------------------
    // object currently at the tail of the fifo
    desc_aw_t current_aw_req;
    // control signals
    logic aw_emitter_full;
    logic aw_emitter_empty;
    logic aw_emitter_push;
    logic aw_emitter_pop;

    // instantiate a fifo to buffer the address write requests
    fifo_v3 #(
        .FALL_THROUGH(1'b0),
        .dtype       (desc_aw_t),
        .DEPTH       (ReqFifoDepth)
    ) i_fifo_aw_emitter (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .flush_i   (1'b0),
        .testmode_i(1'b0),
        .full_o    (aw_emitter_full),
        .empty_o   (aw_emitter_empty),
        .usage_o   (),
        .data_i    (write_req_i.aw),
        .push_i    (aw_emitter_push),
        .data_o    (current_aw_req),
        .pop_i     (aw_emitter_pop)
    );

    //--------------------------------------
    // W emitter
    //--------------------------------------
    // object currently at the tail of the fifo
    desc_w_t current_w_req;
    // control signals
    logic w_emitter_full;
    logic w_emitter_empty;
    logic w_emitter_push;
    logic w_emitter_pop;

    // instanciate a fifo to buffer the write requests
    fifo_v3 #(
        .FALL_THROUGH(1'b0),
        .dtype       (desc_w_t),
        .DEPTH       (ReqFifoDepth)
    ) i_fifo_w_emitter (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .flush_i   (1'b0),
        .testmode_i(1'b0),
        .full_o    (w_emitter_full),
        .empty_o   (w_emitter_empty),
        .usage_o   (),
        .data_i    (write_req_i.w),
        .push_i    (w_emitter_push),
        .data_o    (current_w_req),
        .pop_i     (w_emitter_pop)
    );    

    //--------------------------------------
    // instantiate of the data path
    //--------------------------------------    
    data_t          w_data;
    strb_t          w_strb;
    logic           w_valid;
    logic           w_last;
    logic           w_ready;
    xdma_data_path #(
        .DataWidth  (DataWidth)        
    ) i_xdma_data_path(
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),
        .data_i          (data_i),
        .data_valid_i    (data_valid_i),
        .data_ready_o    (data_ready_o),
        .w_num_beats_i   (current_w_req.num_beats),
        .w_is_single_i   (current_w_req.is_single),
        .w_is_write_data_i(current_w_req.is_write_data),
        .w_dp_valid_i    (~w_emitter_empty),
        .w_dp_ready_o    (w_emitter_pop),
        .w_data_o        (w_data),
        .w_strb_o        (w_strb),
        .w_last_o        (w_last),
        .w_valid_o       (w_valid),
        .w_ready_i       (w_ready),
        .w_grant_i       (grant_i)
    )
    
    //--------------------------------------
    // Refill control
    //--------------------------------------
    // the aw and w fifos of both channels are filled
    // together, as request come bundled.
    always_comb begin : proc_refill

        // Write related channels
        w_ready_o          = ~aw_emitter_full & ~w_emitter_full;
        w_emitter_push     = w_valid_i & w_ready_o;
        aw_emitter_push    = w_valid_i & w_ready_o;
    end



    //--------------------------------------
    // Bus control
    //--------------------------------------
    // here the AXI bus is unpacked/packed.
    always_comb begin : proc_axi_packer
        // We do not need the ar/r right now
        // We tie them to zero
        axi_dma_req_o          = '0;
        // assign W signals
        axi_dma_req_o.w.data   = w_data;
        axi_dma_req_o.w.strb   = w_strb;
        axi_dma_req_o.w.last   = w_last;
        axi_dma_req_o.w_valid  = w_valid;
        w_ready                = axi_dma_res_i.w_ready;
        // AW signals
        axi_dma_req_o.aw.id    = current_aw_req.id;
        axi_dma_req_o.aw.addr  = current_aw_req.addr;
        axi_dma_req_o.aw.len   = current_aw_req.len;
        axi_dma_req_o.aw.size  = current_aw_req.size;
        axi_dma_req_o.aw.burst = current_aw_req.burst;
        axi_dma_req_o.aw.cache = current_aw_req.cache;
        axi_dma_req_o.aw_valid = ~aw_emitter_empty;
        aw_emitter_pop         = axi_dma_res_i.aw_ready & axi_dma_req_o.aw_valid;
        // B signals
        // we are always ready to accept b signals, as we do not need them
        // inside the DMA (we don't care if write failed)
        axi_dma_req_o.b_ready  = 1'b1;
    end

    //--------------------------------------
    // Trans done control
    //--------------------------------------
    
    // Here we use a counter to track the trans_len
    logic [9:0] trans_len_q, trans_len_d;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
           trans_len_q <= '0;
        end else begin
           trans_len_q <= trans_len_d;
        end
    end
    always_comb begin
        trans_len_d = trans_len_q;
        if (w_valid_i) trans_len_d = write_req_i.transfer.total_len;
        if (trans_complete_o) trans_len_d = '0;
    end

    // Here we use a counter to track the handshake signal from the W
    // 16 bit counter
    // at most 2^16*64B = 2^22B = 4MB
    logic clear_counter;
    logic en_counter;
    logic [15:0] counter_q;
    counter #(
        .WIDTH (16)
    ) i_trans_counter (
        .clk_i       ( clk_i              ),
        .rst_ni      ( rst_ni             ),
        .clear_i     ( clear_counter      ),
        .en_i        ( en_counter         ),
        .load_i      ( '0                 ),
        .down_i      ( '0                 ),
        .d_i         ( '0                 ),
        .q_o         ( counter_q          ),
        .overflow_o  (                    )
    );
    assign en_i = w_valid && w_ready;
    assign clear_i = (counter_q==trans_len_q) ;
    assign trans_complete_o = clear_i;   
endmodule