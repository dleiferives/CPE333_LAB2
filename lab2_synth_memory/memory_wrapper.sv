
module memory_wrapper
#(
    parameter USE_CACHE=1,
    parameter USE_SYNTH=1
 )
(
    MEM_CLK,MEM_ADDR1,MEM_ADDR2,MEM_DIN2,MEM_WRITE2,MEM_READ1,MEM_READ2,MEM_DOUT1,MEM_DOUT2, strobe, mem_valid1, mem_valid2, rst
    );
  
    input [31:0] MEM_ADDR1;     //Instruction Memory Port
    input [31:0] MEM_ADDR2;     //Data Memory Port
    input MEM_CLK;
    input [31:0] MEM_DIN2;
    input MEM_WRITE2;
    input MEM_READ1;
    input MEM_READ2;
    output logic [31:0] MEM_DOUT1;
    output logic [31:0] MEM_DOUT2;
    input [3:0] strobe;
    output logic mem_valid1;
    output logic mem_valid2;
    input logic rst;
           
    mem_itf itf(MEM_CLK); //,rst);           //BUS between the CPU and Cache   (OR CPU to MEMORY w/ no cache)
    //assign rst = 
    int timeout = 100000000;   // Feel Free to adjust the timeout value

    //Translate OTTER memory bus signals to parameterized memory interface
    logic MEM_READ2_r;
    always_ff @ (posedge MEM_CLK) begin
        if(MEM_READ1) MEM_DOUT1 <= itf.mem_rdata;
        if(MEM_READ2) MEM_DOUT2 <= itf.mem_rdata;
        MEM_READ2_r <= MEM_READ2;
    end

    assign mem_valid1 = itf.mem_resp; //(MEM_READ1) ? itf.mem_resp : 0;
    assign mem_valid2 = itf.mem_resp; //(MEM_READ2) ? itf.mem_resp : 0;
    
    assign itf.mem_address = (MEM_READ1) ? MEM_ADDR1 : 
                             (MEM_READ2 | MEM_READ2_r | MEM_WRITE2) ? MEM_ADDR2 : 32'b0;
    assign itf.mem_read = MEM_READ1 | MEM_READ2;
    assign itf.mem_write = MEM_WRITE2;
    assign itf.mem_wdata = MEM_DIN2;
    assign itf.rst = rst;
    assign itf.mem_byte_enable = strobe; 


generate
if(!USE_CACHE) begin
/*****************************************************************************/
    //no Cache  (single 32-bit burst)
    // CPU <-> Mem
    ParamMemory #(25, 13, 1, 32, 512,1) memory(itf);

/*****************************************************************************/
end
else begin    
    mem_itf #(256) ca_itf(MEM_CLK);   //BUS between the Cache and Cache Adapter      
    mem_itf #(32) pmem_itf(MEM_CLK);     //BUS between the Cache Adapter to the Pmem

    //with Cache 256bit cache line, 8 32-bit bursts   
    // CPU <-> Cache <-> CacheAdapter <-> Mem
    
    //No byteEnable (strobe) needed for memory module (used in cache)
    ParamMemory #(25, 13, 8, 256, 512,0) memory(pmem_itf);  

    cache cache(itf, ca_itf);
    cacheline_adaptor cacheline_adaptor(ca_itf, pmem_itf);
end
endgenerate


generate
if(!USE_SYNTH) begin
/************************* Error Halting Conditions **************************/
// Stop simulation on error detection
always @(itf.errcode iff (itf.errcode != 0)) begin
    repeat (30) @(posedge itf.clk);
    $display("TOP: Errcode: %0d", itf.errcode);
    $finish;
end

// Stop simulation on timeout (stall detection), halt
always @(posedge itf.clk) begin
    if (itf.halt)
        $finish;
    if (timeout == 0) begin
        $display("TOP: Timed out");
        $finish;
    end
    timeout <= timeout - 1;
end

// Simulataneous Memory Read and Write
always @(posedge itf.clk iff (itf.mem_read && itf.mem_write))
    $error("@%0t TOP: Simultaneous memory read and write detected", $time);
/*****************************************************************************/
end
endgenerate
endmodule
