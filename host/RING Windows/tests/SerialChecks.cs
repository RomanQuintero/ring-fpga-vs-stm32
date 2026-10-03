using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using PongExperiment;

static class SerialChecks
{
    sealed class FakeConnection : ISerialConnection
    {
        public volatile string Mode = "DOWN";
        public string Side = "R";
        public int Opens;
        public bool Closed;
        public readonly List<long> Ticks = new List<long>();
        private readonly Queue<int> bytes = new Queue<int>();
        public void Open() { if (Mode == "BUSY") throw new UnauthorizedAccessException("Port occupied"); Opens++; Closed = false; }
        public void DiscardInput() { bytes.Clear(); }
        public void Write(string message)
        {
            string[] fields = message.TrimEnd('\n').Split(',');
            if (fields.Length != 13 || fields[0] != "STATE" || fields[3] != Side) throw new Exception("Incorrect state framing");
            long tick = Int64.Parse(fields[2]); lock (Ticks) Ticks.Add(tick);
            if (Mode == "DISCONNECT") throw new IOException("USB disconnected");
            if (Mode == "SILENT") return;
            string response = "ACT,1," + tick + "," + Mode + "\n";
            if (Mode == "STALE") response = "ACT,1," + (tick - 1) + ",UP\n";
            if (Mode == "OVERSIZED") response = new string('x', 200) + "\nACT,1," + tick + ",UP\n";
            foreach (char c in response) bytes.Enqueue(c);
        }
        public int ReadByte()
        {
            if (bytes.Count != 0) return bytes.Dequeue();
            Thread.Sleep(1); throw new TimeoutException();
        }
        public void Dispose() { Closed = true; }
    }
    static void Check(bool condition, string name)
    { if (!condition) throw new Exception("Serial: " + name); }
    static ControllerSnapshot Snapshot(long tick)
    { return new ControllerSnapshot(tick, PaddleSide.Right, 400, 400, 500, 30, 240, 240, 960, 480, 80); }
    static bool WaitUntil(Func<bool> condition)
    {
        var clock = Stopwatch.StartNew();
        while (clock.ElapsedMilliseconds < 1500) { if (condition()) return true; Thread.Sleep(1); }
        return false;
    }
    public static void Run()
    {
        var transport = new FakeConnection();
        var controller = new SerialController(delegate { return transport; }, null);
        Check(controller.Decide(Snapshot(100)) == PaddleAction.Stay, "Initial decision is STAY");
        Check(WaitUntil(delegate { return controller.Telemetry.Received >= 1; }), "Receive real ACT boundary");
        Check(controller.Decide(Snapshot(102)) == PaddleAction.Down, "Apply received DOWN exactly once");
        Check(WaitUntil(delegate { return controller.Telemetry.Received >= 2; }), "Complete preceding request before reset");
        Check(controller.Decide(Snapshot(0)) == PaddleAction.Stay, "Reset discards old response");
        Check(WaitUntil(delegate { return controller.Telemetry.Received >= 3; }), "Receive after reset");
        Check(controller.Decide(Snapshot(2)) == PaddleAction.Down, "Resume hardware decisions after reset");
        controller.Dispose(); Check(controller.WaitForStop(2000) && transport.Closed, "Release port on shutdown");
        lock (transport.Ticks) for (int i = 1; i < transport.Ticks.Count; i++)
            Check(transport.Ticks[i] > transport.Ticks[i - 1], "Wire ticks unique through reset");

        foreach (string mode in new[] { "SILENT", "JUMP", "STALE", "BUSY", "DISCONNECT" })
        {
            var fake = new FakeConnection { Mode = mode };
            var serial = new SerialController(delegate { return fake; }, null);
            Check(serial.Decide(Snapshot(0)) == PaddleAction.Stay, mode + " initial fallback");
            Check(WaitUntil(delegate { var t = serial.Telemetry; return t.Timeouts > 0 || t.ConnectionErrors > 0; }), mode + " diagnosed");
            var timing = Stopwatch.StartNew();
            for (int i = 1; i <= 1000; i++) Check(serial.Decide(Snapshot(i * 2)) == PaddleAction.Stay, mode + " safe fallback");
            Check(timing.ElapsedMilliseconds < 200, mode + " game loop never waits for I/O");
            if (mode == "JUMP" || mode == "STALE") Check(serial.Telemetry.InvalidResponses > 0, mode + " response rejected");
            serial.Dispose(); Check(serial.WaitForStop(2000), mode + " stops");
        }
        var oversized = new FakeConnection { Mode = "OVERSIZED" };
        var framed = new SerialController(delegate { return oversized; }, null);
        framed.Decide(Snapshot(0));
        Check(WaitUntil(delegate { return framed.Telemetry.Received > 0; }), "Resynchronize oversized frame on LF");
        Check(framed.Telemetry.InvalidResponses == 1 && framed.Decide(Snapshot(2)) == PaddleAction.Up, "Use valid frame following invalid line");
        framed.Dispose(); Check(framed.WaitForStop(2000), "Framing test stops");
        DualControllers();
        Console.WriteLine("PASS: serial worker, reset, framing, timeout, stale/invalid ACT, busy port, disconnect and nonblocking fallback checks.");
    }
    static ControllerSnapshot LeftSnapshot(long tick)
    { return new ControllerSnapshot(tick, PaddleSide.Left, 400, 100, 500, 30, 240, 240, 960, 480, 80); }
    static void DualControllers()
    {
        bool rejected = false;
        try { ControllerOptions.Parse(new[] { "--fpga-mode", "serial", "--fpga-port", "com4" }); }
        catch (ArgumentException) { rejected = true; }
        Check(rejected, "Reject duplicate configured ports case-insensitively");
        var configured = ControllerOptions.Parse(new[] { "--fpga-mode", "serial", "--fpga-port", "COM901", "--stm32-port", "COM902" });
        Check(configured.FpgaSerial && configured.Stm32Serial && configured.FpgaPort != configured.Stm32Port, "Independent port selection");
        var left = new FakeConnection { Mode = "UP", Side = "L" };
        var right = new FakeConnection();
        var fpga = new SerialController("COM901", "FPGA", delegate { return left; }, null);
        var stm32 = new SerialController("COM902", "STM32", delegate { return right; }, null);
        rejected = false;
        try { new SerialController("com901", "OTHER", delegate { return new FakeConnection(); }, null); }
        catch (ArgumentException) { rejected = true; }
        Check(rejected, "Reject duplicate controller ownership");
        fpga.Decide(LeftSnapshot(0)); stm32.Decide(Snapshot(0));
        Check(WaitUntil(delegate { return fpga.Telemetry.Received == 1 && stm32.Telemetry.Received == 1; }), "Independent replies on L/R ports");
        Check(fpga.Decide(LeftSnapshot(2)) == PaddleAction.Up && stm32.Decide(Snapshot(2)) == PaddleAction.Down, "Opposite actions independent");
        Check(fpga.Telemetry.Device == "FPGA" && stm32.Telemetry.Port == "COM902", "Metrics identify correct device/port");
        Check(WaitUntil(delegate { return fpga.Telemetry.Received >= 2 && stm32.Telemetry.Received >= 2; }), "Complete before fault");
        left.Mode = "SILENT";
        fpga.Decide(LeftSnapshot(4)); stm32.Decide(Snapshot(4));
        Check(WaitUntil(delegate { return fpga.Telemetry.Timeouts > 0 && stm32.Telemetry.Received >= 3; }), "FPGA timeout with STM32 alive");
        // Queue fresh STM32 state after waiting for the failing side, avoiding expired actions.
        long previous = stm32.Telemetry.Received;
        stm32.Decide(Snapshot(6));
        Check(WaitUntil(delegate { return stm32.Telemetry.Received > previous; }), "STM32 continues despite FPGA timeout");
        Check(stm32.Decide(Snapshot(8)) == PaddleAction.Down && fpga.Decide(LeftSnapshot(6)) == PaddleAction.Stay, "Fault isolated");
        left.Mode = "DISCONNECT";
        fpga.Decide(LeftSnapshot(8));
        Check(WaitUntil(delegate { return fpga.Telemetry.ConnectionErrors > 0; }), "Disconnect diagnosed");
        left.Mode = "UP";
        for (int i = 0; i < 80 && fpga.Telemetry.Received < 3; i++) { fpga.Decide(LeftSnapshot(10 + i * 2)); Thread.Sleep(17); }
        Check(fpga.Telemetry.Received >= 3 && left.Opens >= 2, "Reconnect resumes replies");
        fpga.Dispose(); stm32.Dispose();
        Check(fpga.WaitForStop(2000) && stm32.WaitForStop(2000), "Both workers release ports");
        var absent = new FakeConnection { Mode = "BUSY", Side = "L" };
        var missing = new SerialController("COM901", "FPGA", delegate { return absent; }, null);
        var healthy = new SerialController("COM902", "STM32", delegate { return new FakeConnection(); }, null);
        missing.Decide(LeftSnapshot(0)); healthy.Decide(Snapshot(0));
        Check(WaitUntil(delegate { return missing.Telemetry.ConnectionErrors > 0 && healthy.Telemetry.Received > 0; }), "STM32 present plus FPGA absent");
        Check(missing.Decide(LeftSnapshot(2)) == PaddleAction.Stay, "Absent FPGA fallback");
        missing.Dispose(); healthy.Dispose(); Check(missing.WaitForStop(2000) && healthy.WaitForStop(2000), "Absent-device workers stop");
        Console.WriteLine("PASS: dual serial isolation, L/R actions, distinct ports, duplicate rejection, FPGA absent, timeout isolation and reconnect.");
    }
}
