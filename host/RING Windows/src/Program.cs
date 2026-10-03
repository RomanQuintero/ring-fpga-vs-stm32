using System;
using System.Diagnostics;
using System.IO;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace PongExperiment
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try {
                ControllerOptions options = ControllerOptions.Parse(args);
                if (options.ListPorts) {
                    string ports = SerialPortCatalog.Describe();
                    File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ports.txt"), ports);
                    MessageBox.Show(ports, "RING / Serial ports"); return;
                }
                Application.Run(new PongWindow(options));
            } catch (ArgumentException error) { MessageBox.Show(error.Message, "RING / Configuration error"); }
        }
    }
    public sealed class PongWindow : Form
    {
        private readonly SerialController stm32;
        private readonly SerialController fpga;
        private readonly PongGame game;
        private readonly Timer timer = new Timer();
        private readonly Stopwatch clock = Stopwatch.StartNew();
        private double lastTime, accumulator;
        private bool paused;
        private readonly string verificationDirectory;
        private bool verificationSaved;
        private readonly Color ink = Color.FromArgb(225, 235, 243);
        private readonly Color muted = Color.FromArgb(116, 138, 155);
        private readonly Color cyan = Color.FromArgb(58, 212, 216);
        private readonly Color orange = Color.FromArgb(255, 171, 98);
        public PongWindow(ControllerOptions options)
        {
            if (options.FpgaSerial) fpga = new SerialController(options.FpgaPort, "FPGA");
            try { if (options.Stm32Serial) stm32 = new SerialController(options.Stm32Port, "STM32"); }
            catch { if (fpga != null) fpga.Dispose(); throw; }
            game = new PongGame(fpga == null ? (IController)new SimulatedController() : fpga,
                stm32 == null ? (IController)new SimulatedController() : stm32);
            this.verificationDirectory = options.VerificationDirectory;
            Text = "RING / FPGA " + (fpga == null ? "simulated" : fpga.PortName) +
                " vs STM32 " + (stm32 == null ? "simulated" : stm32.PortName);
            ClientSize = new Size(1100, 760); MinimumSize = new Size(820, 620);
            BackColor = Color.FromArgb(13, 20, 28); ForeColor = ink;
            DoubleBuffered = true; KeyPreview = true; StartPosition = FormStartPosition.CenterScreen;
            timer.Interval = 8; timer.Tick += Advance; timer.Start();
            KeyDown += delegate(object sender, KeyEventArgs e) {
                if (e.KeyCode == Keys.Space) { paused = !paused; accumulator = 0; }
                if (e.KeyCode == Keys.R) { game.Reset(); accumulator = 0; }
                if (e.KeyCode == Keys.Escape) Close();
                Invalidate();
            };
        }
        private void Advance(object sender, EventArgs e)
        {
            double now = clock.Elapsed.TotalSeconds;
            double elapsed = Math.Min(0.1, now - lastTime); lastTime = now;
            if (!paused)
            {
                accumulator += elapsed;
                while (accumulator >= PongGame.DeltaSeconds)
                { game.Step(); accumulator -= PongGame.DeltaSeconds; }
            }
            Invalidate();
            if (verificationDirectory != null && !verificationSaved && game.Tick >= 4800)
            {
                verificationSaved = true;
                Directory.CreateDirectory(verificationDirectory);
                using (var bitmap = new Bitmap(1100, 760))
                {
                    // Use the same renderer at a fixed size, including when minimized.
                    using (var graphics = Graphics.FromImage(bitmap))
                    { graphics.Clear(BackColor); DrawScene(graphics, 1100, 760); }
                    bitmap.Save(Path.Combine(verificationDirectory, "match.png"));
                }
                File.WriteAllText(Path.Combine(verificationDirectory, "match.txt"),
                    "Live WinForms timer: " + game.Tick + " physics steps\r\n" +
                    "Score: " + game.LeftScore + "-" + game.RightScore + "\r\n" +
                    "Paddle hits: " + game.LeftTelemetry.Hits + "/" + game.RightTelemetry.Hits + "\r\n" +
                    "Decisions: " + game.LeftTelemetry.Decisions + "/" + game.RightTelemetry.Decisions + "\r\n" +
                    "FPGA: " + (fpga == null ? "SIMULATED" : fpga.Telemetry.ToString()) + "\r\n" +
                    "STM32: " + (stm32 == null ? "SIMULATED" : stm32.Telemetry.ToString()) + "\r\n");
                Close();
            }
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            if (ClientSize.Width > 0 && ClientSize.Height > 0)
                DrawScene(e.Graphics, ClientSize.Width, ClientSize.Height);
        }
        private void DrawScene(Graphics g, int width, int height)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float scale = Math.Min(width / 1100f, height / 760f);
            g.TranslateTransform((width - 1100 * scale) / 2, (height - 760 * scale) / 2);
            g.ScaleTransform(scale, scale);
            Label(g, "PROJECT 15  /  COMPUTING PARADIGMS", 48, 27, 11, muted);
            Label(g, "PONG", 48, 47, 27, ink);
            Label(g, "WINDOWS HOST   /   DUAL UART", 760, 54, 12, muted);
            Line(g, 48, 96, 1052, 96, Color.FromArgb(38, 53, 67));
            Label(g, "FPGA", 70, 113, 21, cyan);
            Label(g, "Arty A7-35T", 70, 143, 12, muted);
            Label(g, "STM32", 872, 113, 21, orange);
            Label(g, "NUCLEO-H7A3ZI-Q", 872, 143, 12, muted);
            Label(g, game.LeftScore.ToString(), 350, 108, 42, ink);
            Label(g, game.RightScore.ToString(), 695, 108, 42, ink);
            Label(g, "VS", 535, 135, 12, muted);
            float x = 70, y = 186;
            using (var b = new SolidBrush(Color.FromArgb(17, 27, 37))) g.FillRectangle(b, x, y, 960, 480);
            using (var p = new Pen(Color.FromArgb(48, 65, 80))) g.DrawRectangle(p, x, y, 960, 480);
            using (var p = new Pen(Color.FromArgb(42, 58, 72), 2))
            { p.DashPattern = new float[] { 4, 7 }; g.DrawLine(p, 550, y + 16, 550, y + 464); }
            Paddle(g, x + (float)PongGame.LeftX, y + (float)game.LeftY, cyan);
            Paddle(g, x + (float)PongGame.RightX, y + (float)game.RightY, orange);
            using (var b = new SolidBrush(ink)) g.FillEllipse(b,
                x + (float)game.BallX - 7, y + (float)game.BallY - 7, 14, 14);
            if (paused || game.ServeTicks > 0)
            {
                string message = paused ? "PAUSED" : "SERVE IN " + (game.ServeTicks / 120.0).ToString("0.0");
                using (var b = new SolidBrush(Color.FromArgb(230, 17, 27, 37))) g.FillRectangle(b, 445, 385, 210, 60);
                Label(g, message, 473, 403, 18, ink);
            }
            DrawController(g, fpga, game.LeftAction, 70, cyan);
            DrawController(g, stm32, game.RightAction, 650, orange);
            Label(g, "HITS " + game.LeftTelemetry.Hits + "   MISSES " + game.LeftTelemetry.Misses +
                "   DECISIONS " + game.LeftTelemetry.Decisions, 70, 697, 10, muted);
            Label(g, "HITS " + game.RightTelemetry.Hits + "   MISSES " + game.RightTelemetry.Misses +
                "   DECISIONS " + game.RightTelemetry.Decisions, 700, 697, 10, muted);
            Label(g, "SPACE  pause     R  reset     ESC  exit", 70, 731, 10, muted);
            Label(g, "RALLY " + game.RallyHits + "    BEST " + game.LongestRally + "    120 Hz physics / 60 Hz decisions", 610, 731, 10, muted);
        }
        private void DrawController(Graphics g, SerialController controller, PaddleAction action, float x, Color color)
        {
            if (controller == null) { Label(g, "SIMULATED / " + action.ToString().ToUpperInvariant(), x, 677, 11, color); return; }
            SerialTelemetry t = controller.Telemetry;
            string state = t.Status == "TIMEOUT" ? "WAITING (NO ACT)" : t.Status == "UNAVAILABLE" ? "ERROR / RETRYING" : t.Status;
            Label(g, "SERIAL " + t.Port + " / " + state + " / " + action.ToString().ToUpperInvariant(), x, 677, 11, color);
            Label(g, "TX " + t.Sent + " RX " + t.Received + " APPLY " + t.Applied + " TO " + t.Timeouts +
                " BAD " + t.InvalidResponses + " ERR " + t.ConnectionErrors + " " + t.LatencyMs.ToString("0.0") + " ms", x, 714, 9, muted);
        }
        private void Paddle(Graphics g, float x, float y, Color color)
        { using (var b = new SolidBrush(color)) g.FillRectangle(b, x - 6, y - 40, 12, 80); }
        private static void Line(Graphics g, float x, float y, float x2, float y2, Color color)
        { using (var p = new Pen(color)) g.DrawLine(p, x, y, x2, y2); }
        private static void Label(Graphics g, string text, float x, float y, float size, Color color)
        {
            using (var font = new Font("Segoe UI", size, FontStyle.Regular, GraphicsUnit.Pixel))
            using (var brush = new SolidBrush(color)) g.DrawString(text, font, brush, x, y);
        }
        protected override void Dispose(bool disposing)
        { if (disposing) { timer.Dispose(); if (stm32 != null) stm32.Dispose(); if (fpga != null) fpga.Dispose(); } base.Dispose(disposing); }
    }
}
