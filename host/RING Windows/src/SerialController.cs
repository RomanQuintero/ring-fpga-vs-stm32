using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Ports;
using System.Text;
using System.Threading;

namespace PongExperiment
{
    public sealed class SerialTelemetry
    {
        public string Device { get; internal set; }
        public string Port { get; internal set; }
        public string Status { get; internal set; }
        public string LastError { get; internal set; }
        public long Sent { get; internal set; }
        public long Received { get; internal set; }
        public long Applied { get; internal set; }
        public long Timeouts { get; internal set; }
        public long InvalidResponses { get; internal set; }
        public long ConnectionErrors { get; internal set; }
        public long Skipped { get; internal set; }
        public double LatencyMs { get; internal set; }
        public override string ToString()
        {
            return String.Format(CultureInfo.InvariantCulture,
                "{10} {11} {0}: sent={1}, received={2}, applied={3}, latency={4:0.00}ms, timeouts={5}, invalid={6}, connectionErrors={7}, skipped={8}, lastError={9}",
                Status, Sent, Received, Applied, LatencyMs, Timeouts, InvalidResponses, ConnectionErrors, Skipped, LastError, Device, Port);
        }
    }
    internal interface ISerialConnection : IDisposable
    {
        void Open();
        void DiscardInput();
        void Write(string message);
        int ReadByte();
    }
    internal sealed class PortConnection : ISerialConnection
    {
        private readonly SerialPort port;
        public PortConnection(string portName) { port = new SerialPort(portName, 115200, Parity.None, 8, StopBits.One) {
            Handshake = Handshake.None, DtrEnable = false, RtsEnable = false,
            Encoding = Encoding.ASCII, NewLine = "\n", ReadTimeout = 2, WriteTimeout = 15
        }; }
        public void Open() { port.Open(); }
        public void DiscardInput() { port.DiscardInBuffer(); }
        public void Write(string message) { port.Write(message); }
        public int ReadByte() { return port.ReadByte(); }
        public void Dispose() { port.Dispose(); }
    }
    public sealed class SerialController : IController, IDisposable
    {
        private const double DeadlineMs = 1000.0 / 60;
        private readonly object gate = new object();
        private readonly AutoResetEvent wake = new AutoResetEvent(false);
        private readonly Func<ISerialConnection> createConnection;
        private readonly string logPath;
        private readonly Thread worker;
        private ControllerSnapshot pending;
        private int generation, pendingGeneration, resultGeneration;
        private long lastTick = -1, resultTick;
        // Keep v1's integer tick unique across match resets and host restarts.
        private long wireTick = DateTime.UtcNow.Ticks;
        private long wireOffset;
        private int wireGeneration = -1;
        private PaddleAction result;
        private bool ready, stopping;
        private long receivedAt;
        private string status = "CONNECTING", lastError = "";
        private long sent, received, applied, timeouts, invalid, connectionErrors, skipped;
        private double latency;

        private static readonly object portGate = new object();
        private static readonly System.Collections.Generic.HashSet<string> ownedPorts =
            new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase);
        public string PortName { get; private set; }
        public string DeviceName { get; private set; }
        public SerialController() : this("COM4", "STM32") { }
        public SerialController(string portName, string deviceName)
            : this(portName, deviceName, delegate { return new PortConnection(ControllerOptions.NormalizePort(portName)); },
                Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "logs", deviceName.ToLowerInvariant() + "-uart.log")) { }
        internal SerialController(Func<ISerialConnection> factory, string logPath)
            : this("COM4", "STM32", factory, logPath) { }
        internal SerialController(string portName, string deviceName, Func<ISerialConnection> factory, string logPath)
        {
            PortName = ControllerOptions.NormalizePort(portName); DeviceName = deviceName;
            createConnection = factory; this.logPath = logPath;
            lock (portGate) {
                if (!ownedPorts.Add(PortName)) throw new ArgumentException("Serial port already assigned: " + PortName);
            }
            worker = new Thread(Run) { IsBackground = true, Name = DeviceName + " " + PortName + " UART" };
            try { worker.Start(); } catch { lock (portGate) ownedPorts.Remove(PortName); throw; }
        }
        public SerialTelemetry Telemetry
        {
            get { lock (gate) return new SerialTelemetry { Device = DeviceName, Port = PortName, Status = status, LastError = lastError,
                Sent = sent, Received = received, Applied = applied, Timeouts = timeouts,
                InvalidResponses = invalid, ConnectionErrors = connectionErrors,
                Skipped = skipped, LatencyMs = latency }; }
        }
        public PaddleAction Decide(ControllerSnapshot snapshot)
        {
            lock (gate)
            {
                if (stopping) return PaddleAction.Stay;
                if (snapshot.Tick < lastTick) { generation++; ready = false; pending = null; }
                lastTick = snapshot.Tick;
                PaddleAction action = PaddleAction.Stay;
                if (ready && resultGeneration == generation && snapshot.Tick > resultTick &&
                    snapshot.Tick - resultTick <= 2 && MillisecondsSince(receivedAt) <= 2 * DeadlineMs)
                { action = result; applied++; }
                ready = false; // Never retain a hardware action across a failed decision.
                if (pending != null) skipped++;
                pending = snapshot; pendingGeneration = generation;
                wake.Set();
                return action;
            }
        }
        private static double MillisecondsSince(long timestamp)
        { return (Stopwatch.GetTimestamp() - timestamp) * 1000.0 / Stopwatch.Frequency; }
        private void Run()
        {
            ISerialConnection connection = null;
            try
            {
                Log("START " + DeviceName + " " + PortName + " 115200 8N1 flow=none responseDeadline=16.67ms");
                while (true)
                {
                    lock (gate) { if (stopping) break; }
                    if (connection == null)
                    {
                        try {
                            connection = createConnection(); connection.Open(); connection.DiscardInput();
                            lock (gate) { status = "WAITING"; lastError = ""; ready = false; }
                            Log("PORT OPEN " + DeviceName + " " + PortName + " waiting for valid ACT");
                        } catch (Exception error) {
                            if (connection != null) { try { connection.Dispose(); } catch (Exception) { } connection = null; }
                            Failure(error); // Retry on the worker, never on the game thread.
                            for (int i = 0; i < 100; i++) {
                                lock (gate) { if (stopping) break; }
                                Thread.Sleep(10);
                            }
                            continue;
                        }
                    }
                    ControllerSnapshot request; int requestGeneration;
                    lock (gate) {
                        request = pending; requestGeneration = pendingGeneration; pending = null;
                    }
                    if (request == null) { wake.WaitOne(100); continue; }
                    try { Exchange(connection, request, requestGeneration); }
                    catch (Exception error) {
                        Failure(error);
                        try { connection.Dispose(); } catch (Exception) { }
                        connection = null;
                    }
                }
            }
            finally
            {
                if (connection != null) { try { connection.Dispose(); } catch (Exception) { } }
                Log("STOP " + Telemetry);
                lock (gate) { stopping = true; ready = false; wake.Dispose(); }
                lock (portGate) ownedPorts.Remove(PortName);
            }
        }
        private void Exchange(ISerialConnection connection, ControllerSnapshot request, int requestGeneration)
        {
            if (wireGeneration != requestGeneration)
            { wireOffset = wireTick + 2 - request.Tick; wireGeneration = requestGeneration; }
            long tick = Math.Max(wireTick + 2, wireOffset + request.Tick);
            wireTick = tick;
            var wireState = new ControllerSnapshot(tick, request.Side, request.BallX, request.BallY,
                request.BallVelocityX, request.BallVelocityY, request.OwnPaddleY, request.OpponentPaddleY,
                request.FieldWidth, request.FieldHeight, request.PaddleHeight);
            // Discard old/partial frames, then LF also resynchronizes the firmware after timeout.
            connection.DiscardInput();
            long started = Stopwatch.GetTimestamp();
            connection.Write(UartProtocol.Serialize(wireState));
            lock (gate) { sent++; }
            var line = new StringBuilder(); bool discard = false;
            while (MillisecondsSince(started) < DeadlineMs)
            {
                lock (gate) { if (stopping || generation != requestGeneration) return; }
                int value;
                try { value = connection.ReadByte(); }
                catch (TimeoutException) { continue; }
                if (value == '\n')
                {
                    PaddleAction action;
                    if (!discard && UartProtocol.TryParseAction(line.ToString(), tick, out action))
                    {
                        double elapsed = MillisecondsSince(started);
                        if (elapsed >= DeadlineMs) break;
                        long accepted;
                        lock (gate) {
                            if (generation != requestGeneration || stopping) return;
                            result = action; resultTick = request.Tick; resultGeneration = requestGeneration;
                            receivedAt = Stopwatch.GetTimestamp(); ready = true; received++;
                            latency = elapsed; status = "CONNECTED"; lastError = ""; accepted = received;
                        }
                        if (accepted == 1 || accepted % 60 == 0)
                            Log("ACT " + DeviceName + " " + PortName + " tick=" + tick + " gameTick=" + request.Tick + " action=" + action + " " + Telemetry);
                        return;
                    }
                    lock (gate) { invalid++; ready = false; }
                    Log("INVALID " + DeviceName + " " + PortName + " expectedTick=" + tick + " line=" + (discard ? "<oversized/non-ASCII>" : line.ToString()));
                    line.Clear(); discard = false;
                }
                else if (!discard)
                {
                    if (value <= 0 || value > 127 || line.Length >= UartProtocol.MaximumLineLength)
                    { discard = true; line.Clear(); }
                    else line.Append((char)value);
                }
            }
            long failures;
            lock (gate) { timeouts++; failures = timeouts; ready = false; status = "TIMEOUT"; lastError = "No valid ACT within 16.67ms"; }
            if (failures == 1 || failures % 60 == 0) Log("TIMEOUT " + DeviceName + " " + PortName + " " + Telemetry);
        }
        private void Failure(Exception error)
        {
            lock (gate) {
                connectionErrors++; if (error is TimeoutException) timeouts++;
                ready = false; status = "UNAVAILABLE"; lastError = error.Message;
            }
            Log("ERROR " + DeviceName + " " + PortName + " " + error.GetType().Name + ": " + error.Message);
        }
        private void Log(string message)
        {
            if (logPath == null) return;
            try {
                Directory.CreateDirectory(Path.GetDirectoryName(logPath));
                File.AppendAllText(logPath, DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture) + " " + message + Environment.NewLine);
            } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
        public void Dispose()
        {
            lock (gate) { if (stopping) return; stopping = true; ready = false; pending = null; wake.Set(); }
            // Worker owns and disposes the port; closing the UI never waits for I/O.
        }
        internal bool WaitForStop(int milliseconds) { return worker.Join(milliseconds); }
    }
}
