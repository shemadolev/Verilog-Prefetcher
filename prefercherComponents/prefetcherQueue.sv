/* Module name: prefetcherQueue
 * Description: prefetchQueue is the base module (queue) of a prefetcher. main capabilities:
 *              * Stores outstanding requests and data responses from DRAM
 *              * Supports 4 opreations, for each block in the queue, according to 4 opcodes: 
                    0- invalidate, 1-read, 2- writeReq, 3-writeResp
                * A watchdog mechanism that evicts old and unused blocks. 
 */
module	prefetcherQueue	(
input logic	    clk,
input logic     resetN,
input logic     [0:BA_ADDR_SIZE-1] inAddr,
input logic	    [0:(1<<LOG_BLOCK_DATA_BYTES)-1] inData,
input logic     [0:1] inOpcode
input logic     [0:WATCHDOG_SIZE-1] watchdogCnt, //the size of the counter that is used to divide the clk freq for the watchdog
	
//local
output logic	[0:(1<<LOG_BLOCK_DATA_BYTES)-1] dataOut,
output logic    valid, // if valid==1'b1 & dataValid==1'b0  ==>> outstanding request
output logic    dataValid, 
//global
output logic	[0:LOG_QUEUE_SIZE] outstandingReqCnt,
output logic	isFull, //If queue is full (=all valid bits are on), don't get extra requests.
// TODO change to almost full
);

parameter LOG_QUEUE_SIZE = 3'd6; // the size of the queue [2^x] 
parameter LOG_BLOCK_DATA_BYTES = 3'd6; //[Bytes]
parameter BA_ADDR_SIZE = 7'd64; // the size of the address [bits]
parameter WATCHDOG_SIZE = 10'd10; // number of bits for the watchdog counter

localparam QUEUE_SIZE = 1<<LOG_QUEUE_SIZE;
localparam BLOCK_SIZE = 1<<LOG_BLOCK_DATA_BYTES;

//queue data
logic [0:BLOCK_SIZE-1] dataMat [0:QUEUE_SIZE-1];
//block metadata
logic [0:QUEUE_SIZE-1] validVec, dataValidVec, outstandingReqVec, ToCounterVec;
logic [0:BA_ADDR_SIZE-1] blockAddrMat [0:QUEUE_SIZE-1]; //should be inserted block aligned
//queue helpers
logic [0:LOG_QUEUE_SIZE-1] headPtr, tailPtr;
logic validReq;
logic addrHit;
logic addrIdx;
logic isEmpty;
// queue alive blocks - mask for the blocks within the range [addrIdx,tailPtr-1]
logic [0:QUEUE_SIZE-1] queueMask;
//watchdog
logic watchdogHit;
logic watchdogHit_d;

//find the valid address index
findValueIdx #(.LOG_VEC_SIZE(LOG_QUEUE_SIZE), .TAG_SIZE(BA_ADDR_SIZE)) findAddrIdx 
                (.inTag(inAddr), .inMat(blockAddrMat), .valid(validVec),
                 .hit(addrHit), .matchIdx(addrIdx)
                 );
//count the number of outstanding requests
onesCnt #(.LOG_VEC_SIZE(LOG_QUEUE_SIZE)) outstandingReqs 
                (.A(outstandingReqVec), 
                 .ones(outstandingReqCnt)
                );
// queue mask - updates mask according to the new headPtr when reading from MOQ
vectorMask #(.LOG_WIDTH(LOG_QUEUE_SIZE)) queueAliveMask
                (.headIdx(addrIdx), .tailIdx(tailPtr),
                 .outMask(queueMask)
                );
// Watchdog
clkDivN #(.WIDTH(WATCHDOG_SIZE)) watchdogFlag
            (.clk(clk), .resetN(resetN), .preScaleValue(watchdogCnt)
             .slowEnPulse(watchdogHit), .slowEnPulse_d(watchdogHit_d)
            );

always_comb begin
    dataOut = dataMat[addrIdx];
    // on addr miss valid==1'b0, top level flushes the queue
    valid = validVec[addrIdx] & addrHit; 
    dataValid = dataValidVec[addrIdx];
    //indicates that the queue is full
    isFull = (tailPtr == headPtr) && !isEmpty;
    isEmpty = ~|validVec;
end

always_ff @(posedge clk or negedge resetN)
begin
	if(!resetN)	begin 
        validVec <= QUEUE_SIZE'b0;
        dataValidVec <= QUEUE_SIZE'b0;
        outstandingReqVec <= QUEUE_SIZE'b0;
        ToCounterVec <= QUEUE_SIZE'b0;
        headPtr <= 1'b0;
        tailPtr <= 1'b0;
	end
	    
    else begin
        // if in the same clk we also get a request the opcode's action
            // will overwrite the relevant fields
        // watchdog description: on each watchdog posedge invalidate blocks where ToCnt==1'b1
            // and toggle ToCnt
        if (watchdogHit && !watchdogHit_d) begin
            ToCounterVec <= ~ToCounterVec;
            validVec <= validVec & ~ToCounterVec;
        end
        
        // invalidateReq
        if((inOpcode==2'd0)) begin
            if (addrHit) begin
                dataValidVec[addrIdx] <= 1'b0;
            end
        end

        // readReq
            // on address match, update headPtr and invalidate all blocks till MOQ ptr
        if((inOpcode==2'd1)) begin
            if (addrHit) begin
                headPtr <= addrIdx;
                validVec <= validVec & queueMask;
            end
        end
        
        // writeReq
        else if(inOpcode==2'd2) begin
            if(!isFull) begin
                validVec[tailPtr] <= 1'b1;
                dataValidVec[tailPtr] <= 1'b0;
                outstandingReqVec[tailPtr] <= 1'b1;
                blockAddrMat[tailPtr] <= inAddr;
                tailPtr <= tailPtr + 1;
                // watchdog logic
                ToCounterVec[addrIdx] <= 1'b0;
            end
        end

        // writeResp
        else if(inOpcode==2'd3) begin
            if(addrHit) begin
                validVec[addrIdx] <= 1'b1;
                dataValidVec[addrIdx] <= 1'b1;
                outstandingReqVec[addrIdx] <= 1'b0;
                dataMat[addrIdx] <= inData;
                // watchdog logic
                ToCounterVec[addrIdx] <= 1'b0; 
            end
        end 
	end
end

endmodule
