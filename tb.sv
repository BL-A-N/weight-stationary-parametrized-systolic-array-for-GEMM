`timescale 1ns/1ps

module tb_ml_accel_single;
    import params_pkg::*;

    // -------------------------------------------------------------------------
    // 1. Signals & Clock/Reset Generation
    // -------------------------------------------------------------------------
    logic aclk;
    logic aresetn;

    // AXI-Lite
    logic [31:0] s_axi_awaddr; logic s_axi_awvalid; logic s_axi_awready;
    logic [31:0] s_axi_wdata;  logic s_axi_wvalid;  logic s_axi_wready;
    logic s_axi_bvalid;        logic s_axi_bready;
    logic [31:0] s_axi_araddr; logic s_axi_arvalid; logic s_axi_arready;
    logic [31:0] s_axi_rdata;  logic s_axi_rvalid;  logic s_axi_rready;

    // AXI-Stream In
    logic [31:0] s_axis_tdata; logic s_axis_tvalid; logic s_axis_tready;

    // AXI-Stream Out
    logic [31:0] m_axis_tdata; logic m_axis_tvalid; logic m_axis_tlast; logic m_axis_tready;

    // 100 MHz Clock (10ns Period)
    initial begin
        aclk = 0;
        forever #5 aclk = ~aclk; 
    end

    // -------------------------------------------------------------------------
    // 2. Device Under Test (DUT)
    // -------------------------------------------------------------------------
    ml_accel_top dut (.*);

    // -------------------------------------------------------------------------
    // 3. AXI Transaction Tasks
    // -------------------------------------------------------------------------
    task axis_send_acts(input [31:0] data);
        begin
            @(posedge aclk);
            s_axis_tdata  = data;
            s_axis_tvalid = 1'b1;
            wait(s_axis_tready == 1'b1);
            @(posedge aclk);
            s_axis_tvalid = 1'b0;
        end
    endtask

    task axil_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge aclk);
            s_axi_awaddr  = addr;
            s_axi_awvalid = 1'b1;
            s_axi_wdata   = data;
            s_axi_wvalid  = 1'b1;
            s_axi_bready  = 1'b1;
            
            wait(s_axi_awready && s_axi_wready);
            @(posedge aclk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid  = 1'b0;
            
            wait(s_axi_bvalid);
            @(posedge aclk);
            s_axi_bready  = 1'b0;
        end
    endtask

    // -------------------------------------------------------------------------
    // 4. Main Test Stimulus
    // -------------------------------------------------------------------------
    logic signed [31:0] logit_out [0:2];
    
    // Variables for timing
    time start_time;
    time end_time;
    time total_time_ns;
    int total_cycles;

    initial begin
        // Prevent 'X' signals by initializing all buses to 0
        aresetn = 0;
        s_axi_awaddr = 0; s_axi_awvalid = 0; s_axi_wdata = 0; s_axi_wvalid = 0; s_axi_bready = 0;
        s_axi_araddr = 0; s_axi_arvalid = 0; s_axi_rready = 0;
        s_axis_tvalid = 0; s_axis_tdata = 0;
        m_axis_tready = 0;
        
        // Assert Reset
        #50;
        aresetn = 1;
        #50;

        $display("==================================================");
        $display("   STARTING END-TO-END LATENCY TEST: 0xEDED1AFE   ");
        $display("==================================================");

        // ---> START TIMING HERE (Before any data is moved) <---
        start_time = $time;
        $display("     [%0t ns] Streaming Input Data In...", start_time);

        // 1. Send Activations via AXI-Stream In
        axis_send_acts(32'hEDED1AFE);//input given here
        
        // 2. Start Inference via AXI-Lite
        $display("     [%0t ns] Input Sent. Triggering AXI-Lite Start...", $time);
        axil_write(32'h0000_0000, 32'h0000_0001);

        // 3. Wait for Hardware to flag core compute done
        wait(dut.infer_done == 1'b1);
        $display("     [%0t ns] Core Compute Complete! Awaiting AXI-Stream Out...", $time);

        // 4. Robust AXI-Stream Capture Loop (Race-Condition Proof)
        m_axis_tready = 1'b1;
        for (int k = 0; k < 3; k++) begin
            wait(m_axis_tvalid == 1'b1);
            logit_out[k] = $signed(m_axis_tdata);
            @(posedge aclk);
            #1; // 1ns delay to prevent delta-cycle race condition
        end
        m_axis_tready = 1'b0;

        // ---> STOP TIMING HERE (After the last output byte is received) <---
        end_time = $time;
        $display("     [%0t ns] Final Output Successfully Received!", end_time);

        // Calculate Timing
        total_time_ns = end_time - start_time;
        total_cycles = total_time_ns / 10; // 10ns clock period

        // 5. Final Report Printout
        $display("\n==================================================");
        $display("               INFERENCE RESULTS                  ");
        $display("==================================================");
        $display("  Input Vector   : 0xEDED1AFE");
        $display("  Logit Output   : [%0d, %0d, %0d]", logit_out[0], logit_out[1], logit_out[2]);
        $display("  Total Time     : %0t ns", total_time_ns);
        $display("  System Cycles  : %0d cycles (Includes AXI Overhead)", total_cycles);
        $display("==================================================");
        
        $finish;
    end
endmodule
