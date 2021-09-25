//Notes: On flush, reset the stride FSM; If stride changes, do nothing (if we'll get hit in MOQ, blocks will pop out, else timeout will expire)

module prefetcherCtrl #(
    parameter ADDR_BITS = 64, //64bit address 2^64
    parameter LOG_OUTSTAND_REQS = 3'd6 //64bit address 2^64
)(
    input logic     clk,
    input logic     en,
    input logic     resetN,

    input logic     [0:ADDR_BITS-1] bar,
    input logic     [0:ADDR_BITS-1] limit,
    input logic     prefetcherHit, //data path output logic valid
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

logic   [0:ADDR_BITS-1] currentStride;
logic   [0:ADDR_BITS-1] storedStride;
logic   [0:ADDR_BITS-1] nxtStride;
logic   [0:ADDR_BITS-1] lastAddr;
logic   [0:ADDR_BITS-1] nxtmasterAddr,
logic   [0:ADDR_BITS-1] prefetchAddr,
logic   reqValid, strideMiss, nxtFlushN, nxtMasterValid, nxtSlaveReady, prefetchAddrInRange, zeroStride;

//FSM States
enum logic [1:0] {s_idle=2'b00, s_arm=2'b01, s_active=2'b10} curState, nxtState;

always_ff (posedge clk or negedge resetN) begin
	if(!resetN)	begin
		curState <= s_idle;
        storedStride <= {ADDR_BITS{1'b0}};
        lastAddr <= {ADDR_BITS{1'b0}};
        flushN <= 1'b1;
        masterValid <= 1'b0;
	end
	else begin
        if(en) begin
            curState <= nxtState;
            lastAddr <= slaveAddr;
            storedStride <= nxtStride;
            flushN <= nxtFlushN;
            masterValid <= nxtMasterValid;
            masterAddr <= nxtmasterAddr;
        end
    end
end

//Next state comb' logic
always_comb begin
    nxtState = curState;
    nxtStride = storedStride;
    nxtFlushN = 1'b1;
    nxtMasterValid = masterValid;
    nxtmasterAddr = masterAddr;
    nxtSlaveReady = 1'b0;

    if(masterValid == 1'b0) begin
        case curState:
            s_idle: begin
                if(reqValid) begin
                    nxtState = s_arm;
                    nxtMasterValid = 1'b1;
                    nxtSlaveReady = 1'b1;
                    nxtmasterAddr = slaveAddr;
                end
            end
            s_arm: begin
                if(reqValid && !zeroStride) begin
                    nxtState = s_active;
                    nxtStride = currentStride;
                    nxtMasterValid = 1'b1;
                    nxtSlaveReady = 1'b1;
                    nxtmasterAddr = slaveAddr;
                end
            end 
            s_active: begin
                if (reqValid && (strideMiss || !prefetcherHit)) begin //TODO refer to dataInValid
                    nxtState = s_arm;
                    nxtFlushN = 1'b0;
                    nxtMasterValid = 1'b1;
                    nxtSlaveReady = 1'b1;
                    nxtmasterAddr = slaveAddr;
                end
                else if((outstandingReqCnt < outstandingReqLimit) && !almostFull && prefetchAddrInRange) begin
                    //Should fetch next block
                    nxtMasterValid = 1'b1;
                    nxtmasterAddr = prefetchAddr;
                end
            end
        endcase
    end

    else if(masterReady) begin //wait for ready from the slave
            nxtMasterValid = 1'b0; // TODO: optimization - don't waste a cycle between requests 
        end
    end
end

//TODO handle miss in prefercherData->flushN => s_idle
//TODO Address calcs should drop the block bits
//TODO is the controller the only one that access the datapath

// signals assignment
assign currentStride = slaveAddr - lastAddr; //TODO: Check if handles correctly negative strides
assign zeroStride = (currentStride == {ADDR_BITS{1'b0}});
assign rangeHit = (slaveAddr >= bar) && (slaveAddr <= limit);
assign reqValid = rangeHit && slaveValid; // the request in the slave port is valid
assign prefetchAddr = masterAddr + storedStride;
assign prefetchAddrInRange = (prefetchAddr >= bar) && (prefetchAddr <= limit);
assign strideMiss = (storedStride != currentStride) && !zeroStride;
endmodule