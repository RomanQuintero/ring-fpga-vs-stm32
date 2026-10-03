using System;
using System.Globalization;
using PongExperiment;

class Checks
{
    static int count;
    static void Assert(bool value, string name)
    { if (!value) throw new Exception(name); count++; }
    sealed class Recorder : IController
    {
        public ControllerSnapshot Last;
        public PaddleAction Decide(ControllerSnapshot snapshot) { Last = snapshot; return PaddleAction.Stay; }
    }
    static void Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--list-ports") { Console.WriteLine(SerialPortCatalog.Describe()); return; }
        var left = new Recorder(); var right = new Recorder(); var game = new PongGame(left, right);
        game.Step();
        Assert(left.Last.Tick == right.Last.Tick && left.Last.BallX == right.Last.BallX, "Both controllers see same state");
        Assert(left.Last.Side == PaddleSide.Left && right.Last.Side == PaddleSide.Right, "Own side identified");
        for (int i = 0; i < 90; i++) game.Step();
        game.BallY = 8; game.VelocityY = -300; game.Step();
        Assert(game.BallY >= PongGame.Radius && game.VelocityY > 0, "Top wall reflection");
        game.BallY = PongGame.Height - 8; game.VelocityY = 300; game.Step();
        Assert(game.BallY <= PongGame.Height - PongGame.Radius && game.VelocityY < 0, "Bottom wall reflection");
        game.BallX = PongGame.LeftX + 14; game.BallY = game.LeftY; game.VelocityX = -540; game.VelocityY = 0;
        game.Step(); Assert(game.VelocityX > 0 && game.LeftTelemetry.Hits == 1, "Left paddle reflection");
        game.BallX = PongGame.RightX - 14; game.BallY = game.RightY; game.VelocityX = 540;
        game.Step(); Assert(game.VelocityX < 0 && game.RightTelemetry.Hits == 1, "Right paddle reflection");
        game.BallX = PongGame.Width + 6; game.VelocityX = 540;
        game.Step(); Assert(game.LeftScore == 1 && game.RightTelemetry.Misses == 1 && game.ServeTicks > 0, "Score and automatic serve");
        game.Reset(); Assert(game.LeftScore == 0 && game.Tick == 0 && game.LeftTelemetry.Hits == 0, "Reset clears match");
        var a = new PongGame(new SimulatedController(), new SimulatedController());
        var b = new PongGame(new SimulatedController(), new SimulatedController());
        for (int i = 0; i < 120 * 600; i++) {
            a.Step(); b.Step();
            Assert(a.LeftY >= 40 && a.LeftY <= 440 && a.RightY >= 40 && a.RightY <= 440, "Paddle bounds");
        }
        Assert(a.BallX == b.BallX && a.BallY == b.BallY && a.LeftScore == b.LeftScore, "Deterministic match");
        Assert(a.LeftTelemetry.Hits > 0 && a.RightTelemetry.Hits > 0, "Autonomous rallies");
        Assert(a.LeftScore + a.RightScore > 0, "Autonomous scoring");
        Assert(a.LeftTelemetry.Decisions == 36000 && a.RightTelemetry.Decisions == 36000, "Equal 60 Hz decisions");
        PaddleAction action;
        Assert(UartProtocol.TryParseAction("ACT,1,42,UP\r\n", 42, out action) && action == PaddleAction.Up, "Valid UART response");
        Assert(!UartProtocol.TryParseAction("ACT,1,41,DOWN", 42, out action) && action == PaddleAction.Stay, "Stale response rejected");
        Assert(!UartProtocol.TryParseAction("ACT,1,42,JUMP", 42, out action), "Invalid action rejected");
        CultureInfo.CurrentCulture = new CultureInfo("es-ES");
        Assert(UartProtocol.Serialize(new ControllerSnapshot(42, PaddleSide.Left, 423.5, 271, -5, 3, 180, 200, 960, 480, 80)) ==
            "STATE,1,42,L,424,271,-5,3,180,200,960,480,80\n", "Invariant integer wire format");
        SerialChecks.Run();
        Console.WriteLine("PASS: " + count + " assertions. Autonomous 10 minutes: " + a.LeftScore + "-" + a.RightScore +
            ", hits " + a.LeftTelemetry.Hits + "/" + a.RightTelemetry.Hits + ".");
    }
}
