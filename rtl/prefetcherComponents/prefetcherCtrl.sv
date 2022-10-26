//Notes: On flush, reset the stride FSM; If stride changes, do nothing (if we'll get hit in MOQ, blocks will pop out, else timeout will expire)

`resetall
`timescale 1ns / 1ps

module prefetcherCtrl #(
    parameter ADDR_BITS = 64, //64bit address 2^64
    parameter OFFSET_BITS = 6, //6 bits - cacheline size == 64B
    parameter LOG_QUEUE_SIZE = 3'd6, // the size of the queue [2^x] 
    parameter WATCHDOG_WIDTH = 10'd10, // number of bits for the watchdog counter
    parameter PRFETCH_FRQ_WIDTH = 3'd6,
    parameter BURST_LEN_WIDTH = 4'd8, //NVDLA max is 3, AXI4 supports up to 8 bits
    parameter TID_WIDTH = 4'd8 //NVDLA max is 3, AXI4 supports up to 8 bits
)(
    input logic     clk,
    input logic     en,
    input logic     resetN,
    input logic     ctrlFlush,

    // Prefetch Data Path
        // Control bits
    output logic    pr_flush, //control bit to flush the queue
    output logic    [0:2] pr_opCode,
    input logic     pr_addrHit,
    input logic     pr_hasOutstanding,
    input logic     [0:LOG_QUEUE_SIZE] pr_reqCnt,
    input logic     pr_almostFull,
    output logic    pr_isCleanup, // indicates that the prefecher is in cleaning
    output logic    pr_context_valid, // burst & tag were learned
       // Read channel
    input logic     pr_r_valid,
        //Read Req Channel
    output logic    [0:ADDR_BITS-1] pr_m_ar_addr,
    output logic    [0:BURST_LEN_WIDTH-1] pr_m_ar_len,
    output logic    [0:TID_WIDTH-1] pr_m_ar_id,

    // Slave AXI ports (PR <-> NVDLA)
        //AR (Read Request)
    input logic s_ar_valid,
    output logic s_ar_ready,
    input logic [0:BURST_LEN_WIDTH-1] s_ar_len, //Read req will be learned only if burst len < no. of blocks
    input logic [0:ADDR_BITS-1] s_ar_addr, 
    input logic [0:TID_WIDTH-1] s_ar_id,
        //R (Read data)
    output logic s_r_valid,
    input logic s_r_ready,
    output logic [0:TID_WIDTH-1] s_r_id,

    // Master AXI ports (PR <-> DDR)
        //AR (Read Request)
    output logic m_ar_valid,
    input logic m_ar_ready,
    output logic [0:BURST_LEN_WIDTH-1] m_ar_len,
    output logic [0:ADDR_BITS-1] m_ar_addr,
    output logic [0:TID_WIDTH-1] m_ar_id,
        //R (Read data)
    input logic m_r_valid,
    output logic m_r_ready,
    input logic [0:TID_WIDTH-1] m_r_id,

    //CR Space
    input logic     [0:ADDR_BITS-1] crs_bar,
    input logic     [0:ADDR_BITS-1] crs_limit,
    input logic     [0:LOG_QUEUE_SIZE] crs_prOutstandingLimit,
    input logic     [0:WATCHDOG_WIDTH-1] crs_watchdogCnt, //the size of the counter that is used to divide the clk freq for the watchdog
    input logic     [0:PRFETCH_FRQ_WIDTH-1] crs_prBandwidthThrottle
);

// Slice's context
logic   [0:ADDR_BITS-1] stride_sampled, stride_reg, stride_next;
logic   [0:TID_WIDTH-1] pr_m_ar_id_next;
logic   [0:BURST_LEN_WIDTH-1] pr_len_reg, pr_len_next;

// Slice's learning 
logic   [0:ADDR_BITS-1] s_ar_addr_prev_reg, s_ar_addr_prev_next;
logic   [0:ADDR_BITS-1] prefetchAddr_reg, prefetchAddr_next; //The address that should be prefetched

// Control bits
logic   reqValid, strideMiss, pr_flush_next, stride_learned, valid_burst;
logic   shouldCleanup, shouldCleanup_context;
logic   slaveReady_next, prefetchAddrInRange, zeroStride, ToBit, prefetchAddr_valid, prefetchAddr_valid_next;

logic   [0:BURST_LEN_WIDTH-1] m_ar_len_next;
logic   [0:ADDR_BITS-1] m_ar_addr_next;
logic   [0:TID_WIDTH-1] m_ar_id_next;

logic m_r_ready_next, m_ar_valid_next;

logic s_r_valid_next;

logic s_ar_ready_next;

// address mask - set cacheline offset bits to 0
localparam [0:ADDR_BITS-1] addr_mask = {{(ADDR_BITS-OFFSET_BITS){1'b1}},{OFFSET_BITS{1'b0}}};
// mask input address
logic [0:ADDR_BITS-1] s_ar_addr_masked;

//watchdog
logic watchdogHit;
logic watchdogHit_d;
logic st_exec_changed;
clkDivN #(.WIDTH(WATCHDOG_WIDTH)) watchdogFlag
            (.clk(clk), .resetN(resetN), .preScaleValue(crs_watchdogCnt),
             .slowEnPulse(watchdogHit), .slowEnPulse_d(watchdogHit_d)
            );

// Prefetching freq.
logic prefetch_freq_pulse;
clkDivN #(.WIDTH(PRFETCH_FRQ_WIDTH)) prefetchFreqClkDiv
            (.clk(clk),
            .resetN(resetN & ~(m_ar_valid & m_ar_ready)), //Reset timer on every successful read req'
            .preScaleValue(crs_prBandwidthThrottle),
            .slowEnPulse(prefetch_freq_pulse)
            );

//FSM States
enum logic [1:0] {ST_PR_IDLE, ST_PR_ARM, ST_PR_ACTIVE, ST_PR_CLEANUP} st_pr_cur, st_pr_next;
enum logic [1:0] {ST_EXEC_IDLE, ST_EXEC_M_AR_POLLING, ST_EXEC_M_R, ST_EXEC_S_R_POLLING} st_exec_cur, st_exec_next;

always_ff @(posedge clk or negedge resetN) begin
	if(!resetN || (watchdogHit && !watchdogHit_d && ToBit==1'b1)) begin
		st_pr_cur <= ST_PR_IDLE;
        st_exec_cur <= ST_EXEC_IDLE;
        stride_reg <= {ADDR_BITS{1'b0}};
        s_ar_addr_prev_reg <= {ADDR_BITS{1'b0}};
        pr_flush <= 1'b1;
        ToBit <= 1'b0;
        prefetchAddr_valid <= 1'b0;
        prefetchAddr_reg <= {ADDR_BITS{1'b0}};
        //AXI ready/valid signals
        s_ar_ready <= 1'b0;
        m_ar_valid <= 1'b0;
        s_r_valid <= 1'b0;
        m_r_ready <= 1'b0;
	end
	else begin
        if(en) begin
            // watchdog description: ToBit += 1 every watchdog rise. Resets on any state change of the EXEC FSM. When reaches max value, flush all.
            if(st_exec_changed)
                ToBit <= 1'b0;
            else if (watchdogHit && !watchdogHit_d)
                ToBit <= ~ToBit;
            
            s_ar_addr_prev_reg <= s_ar_addr_prev_next;
            
            st_pr_cur <= st_pr_next;
            st_exec_cur <= st_exec_next;
            
            stride_reg <= stride_next;
            pr_flush <= pr_flush_next;
            
            prefetchAddr_valid <= prefetchAddr_valid_next;
            prefetchAddr_reg <= prefetchAddr_next;
            
            pr_m_ar_id <= pr_m_ar_id_next;
            pr_len_reg <= pr_len_next;
            
            s_ar_ready <= s_ar_ready_next;

            m_ar_valid <= m_ar_valid_next;
            m_ar_len <= m_ar_len_next;
            m_ar_addr <= m_ar_addr_next;
            m_ar_id <= m_ar_id_next;

            s_r_valid <= s_r_valid_next;
            
            m_r_ready <= m_r_ready_next;
        end
    end
end

//Prefetch FSM comb' logic
always_comb begin
    stride_next = stride_reg;
    prefetchAddr_valid_next = 1'b0;
    st_pr_next = st_pr_cur;
    pr_flush_next = 1'b0;
    pr_len_next = pr_len_reg;
    pr_m_ar_id_next = pr_m_ar_id;
    prefetchAddr_next = prefetchAddr_reg;
    s_ar_addr_prev_next = (s_ar_valid & s_ar_ready) ? s_ar_addr_masked : s_ar_addr_prev_reg;

    case (st_pr_cur)
        ST_PR_IDLE: begin
            if(s_ar_valid & s_ar_ready & valid_burst) begin
                st_pr_next = ST_PR_ARM;
                pr_len_next = s_ar_len;
                pr_m_ar_id_next = s_ar_id;
            end
        end
        ST_PR_ARM: begin
            if(shouldCleanup) begin
                st_pr_next = ST_PR_CLEANUP;
            end
            else if(s_ar_valid & s_ar_ready & ~zeroStride) begin
                st_pr_next = ST_PR_ACTIVE;
                stride_next = stride_sampled;
                prefetchAddr_next = s_ar_addr_masked + stride_sampled;
            end
        end 

        ST_PR_ACTIVE: begin
            if(shouldCleanup) begin
                st_pr_next = ST_PR_CLEANUP;
            end else begin
                if (m_ar_valid & m_ar_ready)
                    prefetchAddr_next = m_ar_addr + stride_reg;

                if((pr_reqCnt < crs_prOutstandingLimit) && ~pr_almostFull && prefetchAddrInRange) //Should fetch next block
                    prefetchAddr_valid_next = 1'b1; 

            end
        end
        ST_PR_CLEANUP: begin
            if(~pr_r_valid & ~pr_hasOutstanding) begin
                st_pr_next = ST_PR_IDLE;
                pr_flush_next = 1'b1;
            end
        end 
    endcase
end

//Execution FSM comb' logic
always_comb begin
    st_exec_next = st_exec_cur;
    
    pr_opCode = 3'd0; //NOP
    
    pr_m_ar_addr = {ADDR_BITS{1'b0}};
    pr_m_ar_len = pr_len_reg;
    
    s_ar_ready_next = 1'b0;
    
    m_ar_len_next = m_ar_len;
    m_ar_addr_next = m_ar_addr;
    m_ar_id_next = m_ar_id;
    m_ar_valid_next = 1'b0;
    
    s_r_valid_next = 1'b0;

    s_r_id = pr_m_ar_id;

    m_r_ready_next = 1'b0;

        case (st_exec_cur)
        ST_EXEC_IDLE: begin 

            if((s_ar_valid & s_ar_ready) | (s_ar_valid & ~shouldCleanup & (st_pr_cur != ST_PR_CLEANUP) & ~pr_almostFull)) begin
                if(s_ar_valid & s_ar_ready) begin
                    //Create read req' PR.Data
                    pr_opCode = 3'd2; //readReqManager
                    pr_m_ar_addr = s_ar_addr_masked;
                    pr_m_ar_len = s_ar_len;
                    s_ar_ready_next = 1'b0;

                    //Create read req' PR->DDR
                    m_ar_len_next = s_ar_len;
                    m_ar_id_next = s_ar_id;
                    m_ar_addr_next = s_ar_addr_masked;
                    
                    if(pr_addrHit) begin
                        m_ar_valid_next = 1'b0;
                        st_exec_next = ST_EXEC_IDLE;
                    end
                    else begin
                        m_ar_valid_next = 1'b1;
                        st_exec_next = ST_EXEC_M_AR_POLLING;
                    end
                end else
                    s_ar_ready_next = 1'b1;
            end
            else if (pr_r_valid) begin
                s_r_valid_next = 1'b1;
                st_exec_next = ST_EXEC_S_R_POLLING;
            end
            else if (m_r_valid & (m_r_id == pr_m_ar_id)) begin
                m_r_ready_next = 1'b1;
                st_exec_next = ST_EXEC_M_R;
            end
            else if (prefetch_freq_pulse & prefetchAddr_valid & ~shouldCleanup & ~pr_almostFull) begin
                pr_opCode = 3'd1; //readReqPref
                pr_m_ar_addr = prefetchAddr_reg;
                
                //Create read req' PR->DDR
                m_ar_len_next = pr_len_reg;
                m_ar_id_next  = pr_m_ar_id;
                m_ar_addr_next = prefetchAddr_reg;

                m_ar_valid_next = 1'b1;
                st_exec_next = ST_EXEC_M_AR_POLLING;
            end
        end
      
        ST_EXEC_S_R_POLLING: begin
            if(s_r_valid & s_r_ready)begin
                s_r_valid_next = 1'b0;
                pr_opCode = 3'd4; //readDataPromise
                st_exec_next = ST_EXEC_IDLE;
            end else
                s_r_valid_next = 1'b1;
        end
      
        ST_EXEC_M_AR_POLLING: begin
            if(m_ar_ready & m_ar_valid) begin
                m_ar_valid_next = 1'b0;
                st_exec_next = ST_EXEC_IDLE;
            end else
                m_ar_valid_next = 1'b1;
        end

        ST_EXEC_M_R: begin
            if(m_r_ready & m_r_valid) begin 
                m_r_ready_next = 1'b1; //Keep reading all available data
                pr_opCode = 3'd3; //readDataSubordinate
                st_exec_next = ST_EXEC_M_R;
            end else begin
                st_exec_next = ST_EXEC_IDLE;
                m_r_ready_next = 1'b0;
            end
        end

    endcase
end

// signals assignment
assign stride_sampled = s_ar_addr_masked - s_ar_addr_prev_reg;
assign zeroStride = (stride_sampled == {ADDR_BITS{1'b0}});
assign prefetchAddrInRange = (prefetchAddr_reg >= crs_bar) && (prefetchAddr_reg <= crs_limit);
assign strideMiss = s_ar_valid && stride_learned && (stride_reg != stride_sampled) && !zeroStride;
assign stride_learned = st_pr_cur == ST_PR_ACTIVE;
assign shouldCleanup = shouldCleanup_context | ~valid_burst | ctrlFlush;
assign shouldCleanup_context = s_ar_valid & pr_context_valid & (s_ar_id != pr_m_ar_id | s_ar_len != pr_len_reg | strideMiss);
assign pr_context_valid = st_pr_cur != ST_PR_IDLE;
assign st_exec_changed = st_exec_cur != st_exec_next;
assign pr_isCleanup = st_pr_cur == ST_PR_CLEANUP;
assign valid_burst = ~|({{(BURST_LEN_WIDTH - LOG_QUEUE_SIZE + 1){1'b1}},{(LOG_QUEUE_SIZE - 1){1'b0}}} & s_ar_len); //Accept only burst len that will be <= 1/2 of QUEUE SIZE
assign s_ar_addr_masked = s_ar_addr & addr_mask;

endmodule

`resetall
