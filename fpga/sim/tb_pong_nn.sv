`timescale 1ns/1ps
module tb_pong_nn;
    logic clk=0, rst=1, start=0;
    logic signed [7:0] x [0:4];
    wire busy, done;
    wire [1:0] action;
    pong_nn dut(.*);
    always #5 clk=~clk;
    integer fd, status, value, expected, count=0, cycles, failures=0;
    integer eh [0:15], eo [0:2];
    initial begin
        fd=$fopen("vectors.txt","r");
        if (!fd) $fatal(1,"Cannot open vectors.txt");
        repeat(3) @(negedge clk);
        rst=0;
        while (!$feof(fd)) begin
            status=$fscanf(fd,"%d",value);
            if (status == 1) begin
                x[0]=value;
                for (int i=1;i<5;i++) begin
                    status=$fscanf(fd,"%d",value); if(status!=1) $fatal; x[i]=value;
                end
                for (int i=0;i<16;i++) begin status=$fscanf(fd,"%d",eh[i]); if(status!=1) $fatal; end
                for (int i=0;i<3;i++) begin status=$fscanf(fd,"%d",eo[i]); if(status!=1) $fatal; end
                status=$fscanf(fd,"%d",expected); if(status!=1) $fatal;
                start=1; @(negedge clk); start=0;
                cycles=0;
                while (!done && cycles<2500) begin @(negedge clk); cycles++; end
                if (!done || busy) $fatal(1,"Handshake/timeout vector %0d",count);
                for (int i=0;i<16;i++) if(dut.hidden_q[i] !== eh[i]) begin
                    failures++; if(failures<10) $display("Hidden mismatch vector %0d neuron %0d",count,i);
                end
                for (int i=0;i<3;i++) if(dut.logits[i] !== eo[i]) begin
                    failures++; if(failures<10) $display("Logit mismatch vector %0d output %0d",count,i);
                end
                if (action !== expected) begin
                    failures++; if(failures<10) $display("Action mismatch vector %0d got %0d expected %0d",count,action,expected);
                end
                count++;
                @(negedge clk);
                if(done) $fatal(1,"done must be a one-cycle pulse");
            end
        end
        $fclose(fd);
        if(count != 30243) $fatal(1,"Unexpected count %0d",count);
        if(failures) $fatal(1,"FAIL %0d discrepancies across %0d vectors",failures,count);
        $display("PASS: %0d vectors; hidden, logits and actions match Python INT8 (100%%)",count);
        $finish;
    end
endmodule
