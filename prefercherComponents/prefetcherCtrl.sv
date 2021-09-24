//Notes: On flush, reset the stride FSM; If stride changes, do nothing (if we'll get hit in MOQ, blocks will pop out, else timeout will expire)

module prefetcherCtrl(
    
    input logic     clk,
    input logic     en,
    input logic     resetN,

    input logic     [0:ADDR_BITS-1] bar,
    input logic     [0:ADDR_BITS-1] limit,
    input logic     addrReqHit, //data path output logic valid
    input logic     almostFull,
    input logic     outstandingReqCnt,
    input logic     outstandingReqLimit,

    output logic    rangeHit, //indicates that the request is the prefetcher range
    output logic    flushN, //control bit to flush the queue
    
    //AXI slave port
    input logic     slaveValid, //valid only on read req (given by the top) write reqs aren't relevant for this module
    input logic     [0:ADDR_BITS-1] slaveAddr,
    output logic    slaveReady, //TODO  
    //AXI master port
    output logic    masterValid,
    output logic    [0:ADDR_BITS-1] masterAddr,
    input  logic    masterReady
);

parameter ADDR_BITS = 64; //64bit address 2^64
parameter LOG_OUTSTAND_REQS = 3'd6; //64bit address 2^64

logic   [0:ADDR_BITS-1] currentStride;
logic   [0:ADDR_BITS-1] storedStride;
logic   [0:ADDR_BITS-1] nxtStride;
logic   [0:ADDR_BITS-1] lastAddr;
logic   [0:ADDR_BITS-1] nxtmasterAddr,
logic   [0:ADDR_BITS-1] addrStrideAhead,
logic   strideHit, nxtFlushN, nxtmasterValid, addrStrideAheadInRange;

//FSM States
enum logic [1:0] {s_idle=2'b00, s_arm=2'b01, s_active=2'b10} curState, nxtState;

always_ff (posedge clk or negedge resetN) begin
	if(!resetN)	begin
		curState <= s_idle;
        storedStride <= (ADDR_BITS)'d0;
        lastAddr <= (ADDR_BITS)'d0;
        flushN <= 1'b1;
        masterValid <= 1'b0;
	end
	else begin
        if(en) begin
            curState <= nxtState;
            lastAddr <= slaveAddr;
            storedStride <= nxtStride;
            flushN <= nxtFlushN;
            masterValid <= nxtmasterValid;
            masterAddr <= nxtmasterAddr;
        end
    end
end

//Next state comb' logic
always_comb begin
    nxtState = curState;
    nxtStride = storedStride;
    nxtFlushN = 1'b1;
    nxtmasterValid = masterValid;
    nxtmasterAddr = masterAddr;

    if(masterValid == 1'b1) begin //wait for ready from the slave
        if(masterReady) begin
            nxtmasterValid = 1'b0;
        end
    end
    else begin
        case curState:
            s_idle: begin
                if(rangeHit && slaveValid) begin
                    nxtState = s_arm;
                    nxtmasterValid = 1'b1;
                    nxtmasterAddr = slaveAddr;
                end
            end
            s_arm: begin
                if((currentStride != (ADDR_BITS)'d0) && rangeHit && slaveValid) begin
                    nxtState = s_active;
                    nxtStride = currentStride;
                    nxtmasterValid = 1'b1;
                    nxtmasterAddr = slaveAddr;
                end
            end
            s_active: begin
                if (!strideHit && (currentStride != (ADDR_BITS)'d0) && rangeHit && slaveValid) begin
                    nxtState = s_arm;
                    nxtFlushN = 1'b0;
                    nxtmasterValid = 1'b1;
                    nxtmasterAddr = slaveAddr;
                end
                else if((outstandingReqCnt < outstandingReqLimit) && !almostFull && addrStrideAheadInRange) begin
                    //Should fetch next block
                    nxtmasterValid = 1'b1;
                    nxtmasterAddr = addrStrideAhead;
                end
            end
        endcase
    end
end
//TODO handle miss in prefercherData->flushN => s_idle
//TODO Address calcs should drop the block bits

// signals assignment
assign rangeHit = (slaveAddr >= bar) && (slaveAddr <= limit);
assign addrStrideAhead = masterAddr + storedStride;
assign addrStrideAheadInRange = (addrStrideAhead >= bar) && (addrStrideAhead <= limit);
assign currentStride = slaveAddr - lastAddr; //TODO: Check if handles correctly negative strides
assign strideHit = (storedStride == currentStride) && slaveValid;
endmodule