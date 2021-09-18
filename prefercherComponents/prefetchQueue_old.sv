module	prefetchQueue	(
    clk,            //<i
    resetN,         //<i
    pushEn,         //<i
    readEn,         //<i
    inAddr,         //<i
    inData,         //<i
    
    ready,          //>o
    responseValid,  //>o
    isFull,         //>o
    readHit,        //>o
    readData        //>o
);

input	clk;
input	resetN;
output  ready;          //'1' when ready to recieve request; '0' when busy
output  responseValid;  //'1' when response (output) should be read

input   pushEn;
input   readEn;
input	[0:ADDR_BITS-1]	inAddr;
input   reg [0:DATA_BITS-1]	inData;
    
output  isFull;
output  readHit;
output  [0:DATA_BITS-1]	readData;

parameter DATA_BITS = 512; //Maximum data block size
parameter ADDR_BITS = 64; //64bit address
          
parameter REG_DEPTH = 5; 

wire [0:REG_DEPTH-1] valid;
wire [DATA_BITS-1:0][REG_DEPTH-1:0] dataValues;
wire [ADDR_BITS-1:0][REG_DEPTH-1:0] addrValues;
wire shouldPop;
wire headPointer; //The block index that holds the head of queue

wire [ADDR_BITS-1:0] headAddr;

reg [0:ADDR_BITS-1] _inAddr; //Stores inAddr values, until pops MOQ

reg headDirty;
reg [DATA_BITS-1:0] dirtyData;

wire [ADDR_BITS+DATA_BITS-1:0][REG_DEPTH-1:0] packedData;

assign isFull = valid[REG_DEPTH-1];
assign addrValues = packedData[ADDR_BITS-1:0];
assign dataValues = packedData[ADDR_BITS+DATA_BITS-1:ADDR_BITS];

doubleQueue #(.DATA_BITS(ADDR_BITS + DATA_BITS), .REG_DEPTH(REG_DEPTH))
    queue(
        .clk(clk), .resetN(resetN), .pushEn(pushEn), .popEn(shouldPop), .inVector({inAddr,inData}), //Inputs
        .dataVal(packedData), .valid(valid) //Outputs
    );

// ------- Implement logic: ------
assign readHit = ...; //If readEn AND any of addrValues values match inAddr (with genvar i)
assign headPointer = ...; //TODO caclulate based on the most right '1' bit in 'valid' bus
assign shouldPop = ...; //If readHit, using FSM continue popping until the address in head of queue matches inAddr


// ------- Implement FSM: ------
// 1. On write / read request, pop the head until head's address matches the requested address.


always @(posedge clk or negedge resetN)
begin
	if(!resetN)	begin
		...;
	end
	else begin
		...;
	end
end

endmodule
