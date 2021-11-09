//Notes: On flush, reset the stride FSM; If stride changes, do nothing (if we'll get hit in MOQ, blocks will pop out, else timeout will expire)

module prefetcherCtrl #(
    parameter ADDR_BITS = 64, //64bit address 2^64
    parameter LOG_QUEUE_SIZE = 3'd6, // the size of the queue [2^x] 
    parameter WATCHDOG_SIZE = 10'd10, // number of bits for the watchdog counter
    parameter LOG_BLOCK_DATA_BYTES = 3'd6, //[Bytes]
    localparam BLOCK_DATA_SIZE_BITS = (1<<LOG_BLOCK_DATA_BYTES)<<3, //shift left by 3 to convert Bytes->bits
    parameter BURST_LEN_WIDTH = 4'd8, //NVDLA max is 3, AXI4 supports up to 8 bits
    parameter TID_WIDTH = 4'd8 //NVDLA max is 3, AXI4 supports up to 8 bits
)(
    input logic     clk,
    input logic     en,
    input logic     resetN,
    input logic     ctrlFlushN,

    input logic     almostFull,
    input logic     [0:LOG_QUEUE_SIZE] prefetchReqCnt,
    input logic     pr_r_valid,
    input logic     pr_r_in_last,
    input logic     [0:BLOCK_DATA_SIZE_BITS-1] pr_r_in_data,
    input logic     pr_addrHit,
    input logic     pr_hasOutstanding,

    output logic    pr_r_out_last,
    output logic    [0:BLOCK_DATA_SIZE_BITS-1] pr_r_out_data,
    output logic    [0:ADDR_BITS-1] pr_addr,

    output logic    [0:2] pr_opCode,
    output logic    rangeHit, //indicates that the request is the prefetcher range
    output logic    [0:BURST_LEN_WIDTH-1] burstLen,
    output logic    [0:TID_WIDTH-1] tagId,
    output logic    dataFlushN, //control bit to flush the queue
    output logic    isCleanup, // indicates that the prefecher is in cleaning       
    
    //AXI AR (Read Request) slave port
    input logic s_ar_valid,
    output logic s_ar_ready,
    input logic [0:BURST_LEN_WIDTH-1]s_ar_len,
    input logic [0:ADDR_BITS-1] s_ar_addr, 
    input logic [0:TID_WIDTH-1] s_ar_id,

    //AXI AR (Read Request) master port
    output logic m_ar_valid,
    input logic m_ar_ready,
    output logic [0:BURST_LEN_WIDTH-1] m_ar_len,
    output logic [0:ADDR_BITS-1] m_ar_addr,
    output logic [0:TID_WIDTH-1] m_ar_id,

    //AXI R (Read data) slave port
    output logic s_r_valid,
    input logic s_r_ready,
    output logic s_r_last,
    output logic [0:BLOCK_DATA_SIZE_BITS-1] s_r_data,
    output logic [0:TID_WIDTH-1] s_r_id,

    //AXI R (Read data) master port
    input logic m_r_valid,
    output logic m_r_ready,
    input logic m_r_last,
    input logic [0:BLOCK_DATA_SIZE_BITS-1]  m_r_data,
    input logic [0:TID_WIDTH-1] m_r_id, //todo check this always matches the stored tagId

    //CR Space
    input logic     [0:ADDR_BITS-1] bar,
    input logic     [0:ADDR_BITS-1] limit,
    input logic     [0:LOG_QUEUE_SIZE] windowSize,
    input logic     [0:WATCHDOG_SIZE-1] watchdogCnt //the size of the counter that is used to divide the clk freq for the watchdog
);

// Slice's context
    // stride
logic   [0:ADDR_BITS-1] currentStride;
logic   [0:ADDR_BITS-1] storedStride;
logic   [0:ADDR_BITS-1] nxtStride;
    // transaction id
logic   [0:TID_WIDTH-1] nxt_tagId;
    // burst length
logic   [0:BURST_LEN_WIDTH-1] burstLen, nxt_burstLen;

// Slice's learning 
logic   [0:ADDR_BITS-1] s_ar_addr_prev;
logic   [0:ADDR_BITS-1] prefetchAddr, nxt_prefetchAddr, nxtPpefetchAddr_last;

// Control bits
logic   reqValid, strideMiss, nxt_dataFlushN, nxtMasterValid, nxt_pr_ar_ack;
logic   nxtSlaveReady, prefetchAddrInRange, zeroStride, ToBit, prefetchAddr_valid, nxtPrefetchAddr_valid;
logic    [0:2] nxt_pr_opCode;
logic    [0:ADDR_BITS-1] nxt_pr_addr;
logic    [0:BURST_LEN_WIDTH-1] nxt_m_ar_len;
logic    [0:ADDR_BITS-1] nxt_m_ar_addr;
logic    [0:TID_WIDTH-1] nxt_m_ar_id;

logic nxt_s_r_valid, nxt_s_r_in_last, pr_r_out_last;
logic [0:BLOCK_DATA_SIZE_BITS-1] nxt_s_r_data;

//watchdog
logic watchdogHit;
logic watchdogHit_d;

// Watchdog
clkDivN #(.WIDTH(WATCHDOG_SIZE)) watchdogFlag
            (.clk(clk), .resetN(resetN), .preScaleValue(watchdogCnt)
             .slowEnPulse(watchdogHit), .slowEnPulse_d(watchdogHit_d)
            );

//FSM States
enum logic [1:0] {st_pr_idle, st_pr_arm, st_pr_active, st_pr_cleanup} cur_st_pr, nxt_st_pr;
enum logic [1:0] {st_exec_idle,st_exec_s_ar_polling,st_exec_pr_ar_polling,st_exec_s_r_polling} cur_st_exec, nxt_st_exec;

always_ff @(posedge clk or negedge resetN) begin
	if(!resetN || (watchdogHit && !watchdogHit_d && ToBit==1'b1)) begin
		cur_st_pr <= st_pr_idle;
        cur_st_exec <= st_exec_idle;
        storedStride <= {ADDR_BITS{1'b0}};
        s_ar_addr_prev <= {ADDR_BITS{1'b0}};
        dataFlushN <= 1'b0;
        masterValid <= 1'b0;
        ToBit <= 1'b0;    
	end
	else begin
        if(en) begin
            if (watchdogHit && !watchdogHit_d) begin
                // watchdog description: ToBit += 1 every watchdog rise. Resets on any read request / response. When reaches max value, flush all.
                ToBit <= ~ToBit;
            end
            cur_st_pr <= nxt_st_pr;
            cur_st_exec <= nxt_st_exec;
            
            s_ar_addr_prev <= s_ar_addr;
            storedStride <= nxtStride;
            dataFlushN <= nxt_dataFlushN;
            
            prefetchAddr_valid <= nxtPrefetchAddr_valid;
            prefetchAddr <= nxt_prefetchAddr;
            
            tagId <= nxt_tagId;
            burstLen <= nxt_burstLen;
            
            pr_opCode <= nxt_pr_opCode;
            pr_addr <= nxt_pr_addr;
            
            s_ar_ready <= nxt_s_ar_ready;

            m_ar_len <= nxt_m_ar_len;
            m_ar_addr <= nxt_m_ar_addr;
            m_ar_id <= nxt_m_ar_id;


            s_r_valid <= nxt_s_r_valid;
            s_r_last <= nxt_s_r_in_last;
            s_r_data <= nxt_s_r_data;
            
            pr_r_out_last <= nxt_m_r_last;
            pr_r_out_data <= nxt_m_r_data;

            pr_ar_ack <= nxt_pr_ar_ack;

            m_r_ready <= nxt_m_r_ready;
        end
    end
end

//Prefetch FSM comb' logic
always_comb begin
    nxt_st_pr = cur_st_pr;
    nxtStride = storedStride;
    nxt_dataFlushN = 1'b1;
    nxtPrefetchAddr_valid = 1'b0;
    nxt_burstLen = burstLen;
    nxt_tagId = tagId;
    nxt_prefetchAddr = prefetchAddr;

    // if(masterValid == 1'b0) begin
    case (cur_st_pr)
        st_pr_idle: begin
            if(rangeHit) begin
                nxt_st_pr = st_pr_arm;
                nxt_burstLen = s_ar_len;
                nxt_tagId = s_ar_id;
            end
        end
        st_pr_arm: begin
            if(shouldCleanup) begin
                nxt_st_pr = st_pr_cleanup;
            end
            else if(rangeHit && !zeroStride) begin
                nxt_st_pr = st_pr_active;
                nxtStride = currentStride;
                nxt_prefetchAddr = s_ar_addr + currentStride;
            end
        end 

        st_pr_active: begin
            if(shouldCleanup) begin
                nxt_st_pr = st_pr_cleanup;
            end else begin
                if((prefetchReqCnt < windowSize) && ~almostFull && prefetchAddrInRange) //Should fetch next block
                    nxtPrefetchAddr_valid = 1'b1; 
                 
                if(pr_ar_ack) 
                    nxt_prefetchAddr = prefetchAddr + storedStride;
            end
        end
        st_pr_cleanup: begin
            if(~pr_r_valid & ~hasOutstanding) begin
                nxt_st_pr = st_pr_idle;
                nxt_dataFlushN = 1'b0;
            end
        end 
    endcase
end

//Execution FSM comb' logic
always_comb begin
    nxt_pr_opCode = 3'd0;
    nxt_s_ar_ready = 1'b0;
    nxt_pr_addr = pr_addr;
    
    nxt_m_ar_len = m_ar_len;
    nxt_m_ar_addr = m_ar_addr;
    nxt_m_ar_id = m_ar_id;
    
    nxt_s_r_valid = 1'b0;
    nxt_s_r_in_last = s_r_last;
    nxt_s_r_data = s_r_data;

    nxt_pr_r_out_last = pr_r_out_last;

    s_r_id = tagId;

    nxt_m_r_ready = 1'b0;

    nxt_pr_ar_ack = 1'b0;

    case (cur_st_exec)
        st_exec_idle: begin 
            if(s_ar_valid & ~shouldCleanup & |(cur_st_pr ^ st_pr_cleanup)) begin
                if(s_ar_ready) begin
                    nxt_pr_opCode = 3'd2; //readReqMaster
                    nxt_pr_addr = s_ar_addr;
                    
                    nxt_m_ar_len = s_ar_len;
                    nxt_m_ar_id = s_ar_id;
                    nxt_m_ar_addr = s_ar_addr;

                    nxt_st_exec = st_exec_s_ar_polling;
                end
                else
                    nxt_s_ar_ready = 1'b1;
            end
            else if (pr_r_valid) begin
                nxt_s_r_valid = 1'b1;
                nxt_s_r_in_last = pr_r_in_last;
                nxt_s_r_data = pr_r_data;
                nxt_pr_opCode = 3'd4; //readDataPromise
                nxt_st_exec = st_exec_s_r_polling;
            end
            else if (m_r_valid) begin
                if(m_r_ready) begin
                    nxt_pr_opCode = 3'd3; //readDataSlave
                    nxt_pr_r_out_last = m_r_last;
                    nxt_pr_r_out_data = m_r_data;
                end
                else
                    nxt_m_r_ready = 1'b1;
            end
            else if (prefetchAddr_valid & ~shouldCleanup) begin
                nxt_pr_ar_ack = 1'b1;
                nxt_pr_opCode = 3'd1; //readReqPref
                nxt_pr_addr = prefetchAddr;
                nxt_st_exec = st_exec_pr_ar_polling;
                nxt_m_ar_len = burstLen;
                nxt_m_ar_id  = tagId;
                nxt_m_ar_valid = 1'b1;
            end
        end

        st_exec_s_r_polling: begin
            nxt_s_r_valid = 1'b1;
            if(s_r_ready) begin
                nxt_s_r_valid = 1'b0;
                cur_st_exec = st_exec_idle;
            end
        end

        st_exec_pr_ar_polling: begin
            nxt_m_ar_valid = 1'b1;
            if(m_ar_ready) begin
                nxt_st_exec = st_exec_idle;
                nxt_m_ar_valid = 1'b0;
            end
        end

        st_exec_s_ar_polling: begin
            if(pr_addrHit)
                nxt_st_exec = st_exec_idle;
            else begin
                nxt_m_ar_valid = 1'b1;
                if(m_ar_ready & m_ar_valid) begin
                    nxt_st_exec = st_exec_idle;
                    nxt_m_ar_valid = 1'b0;
                end
            end
        end
    endcase
end

//TODO Address calcs should drop the block bits

// signals assignment
assign currentStride = s_ar_addr - s_ar_addr_prev; //TODO: Check if handles correctly negative strides
assign zeroStride = (currentStride == {ADDR_BITS{1'b0}});
assign rangeHit = s_ar_valid && (s_ar_addr >= bar) && (s_ar_addr <= limit);
assign prefetchAddrInRange = (prefetchAddr >= bar) && (prefetchAddr <= limit);
assign strideMiss = (storedStride != currentStride) && !zeroStride; 
assign shouldCleanup = (s_ar_valid && (s_ar_id != tagId || s_ar_len != burstLen || (!rangeHit && tagId == s_ar_id)))
                        || strideMiss || ctrlFlush;
endmodule