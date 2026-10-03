using System;

namespace PongExperiment
{
    public sealed class SideTelemetry
    {
        public long Decisions { get; internal set; }
        public int Hits { get; internal set; }
        public int Misses { get; internal set; }
    }
    public sealed class PongGame
    {
        public const double Width = 960, Height = 480, PaddleHeight = 80;
        public const double PaddleWidth = 12, LeftX = 32, RightX = Width - 32, Radius = 7;
        public const double DeltaSeconds = 1.0 / 120;
        private const double PaddleSpeed = 270, BallSpeed = 540;
        private readonly IController left, right;
        private int serveNumber;
        public long Tick { get; private set; }
        public double BallX { get; internal set; }
        public double BallY { get; internal set; }
        public double VelocityX { get; internal set; }
        public double VelocityY { get; internal set; }
        public double LeftY { get; internal set; }
        public double RightY { get; internal set; }
        public int LeftScore { get; private set; }
        public int RightScore { get; private set; }
        public int ServeTicks { get; private set; }
        public int RallyHits { get; private set; }
        public int LongestRally { get; private set; }
        public PaddleAction LeftAction { get; private set; }
        public PaddleAction RightAction { get; private set; }
        public SideTelemetry LeftTelemetry { get; private set; }
        public SideTelemetry RightTelemetry { get; private set; }
        public PongGame(IController left, IController right)
        {
            if (left == null || right == null) throw new ArgumentNullException("controller");
            this.left = left; this.right = right; Reset();
        }
        public void Reset()
        {
            Tick = 0; LeftScore = RightScore = RallyHits = LongestRally = serveNumber = 0;
            LeftY = RightY = Height / 2;
            LeftAction = RightAction = PaddleAction.Stay;
            LeftTelemetry = new SideTelemetry(); RightTelemetry = new SideTelemetry();
            Serve();
        }
        private void Serve()
        {
            BallX = Width / 2; BallY = Height / 2; ServeTicks = 90; RallyHits = 0;
            // Fixed sequence makes resets and controller comparisons reproducible.
            double[] angles = { 0.62, -0.78, 0.92, -0.54 };
            double angle = angles[serveNumber % angles.Length];
            VelocityX = Math.Cos(angle) * BallSpeed * (serveNumber % 2 == 0 ? 1 : -1);
            VelocityY = Math.Sin(angle) * BallSpeed;
            serveNumber++;
        }
        public ControllerSnapshot Snapshot(PaddleSide side)
        {
            return new ControllerSnapshot(Tick, side, BallX, BallY, VelocityX, VelocityY,
                side == PaddleSide.Left ? LeftY : RightY,
                side == PaddleSide.Left ? RightY : LeftY, Width, Height, PaddleHeight);
        }
        public void Step()
        {
            if (Tick % 2 == 0)
            {
                var a = Snapshot(PaddleSide.Left); var b = Snapshot(PaddleSide.Right);
                LeftAction = SafeAction(left.Decide(a)); RightAction = SafeAction(right.Decide(b));
                LeftTelemetry.Decisions++; RightTelemetry.Decisions++;
            }
            LeftY = Move(LeftY, LeftAction); RightY = Move(RightY, RightAction);
            Tick++;
            if (ServeTicks > 0) { ServeTicks--; return; }
            double previousX = BallX;
            BallX += VelocityX * DeltaSeconds; BallY += VelocityY * DeltaSeconds;
            if (BallY < Radius) { BallY = 2 * Radius - BallY; VelocityY = Math.Abs(VelocityY); }
            if (BallY > Height - Radius) { BallY = 2 * (Height - Radius) - BallY; VelocityY = -Math.Abs(VelocityY); }
            double leftFace = LeftX + PaddleWidth / 2 + Radius;
            double rightFace = RightX - PaddleWidth / 2 - Radius;
            if (VelocityX < 0 && previousX >= leftFace && BallX <= leftFace)
                Collide(previousX, leftFace, LeftY, true);
            if (VelocityX > 0 && previousX <= rightFace && BallX >= rightFace)
                Collide(previousX, rightFace, RightY, false);
            if (BallX < -Radius) { RightScore++; LeftTelemetry.Misses++; Serve(); }
            else if (BallX > Width + Radius) { LeftScore++; RightTelemetry.Misses++; Serve(); }
        }
        private void Collide(double previousX, double face, double paddleY, bool isLeft)
        {
            // Interpolate contact Y so fast movement cannot jump over a paddle.
            double fraction = (face - previousX) / (BallX - previousX);
            double contactY = BallY - VelocityY * DeltaSeconds * (1 - fraction);
            if (Math.Abs(contactY - paddleY) > PaddleHeight / 2 + Radius) return;
            BallX = face;
            double offset = Math.Max(-1, Math.Min(1, (contactY - paddleY) / (PaddleHeight / 2)));
            double angle = offset * Math.PI / 3;
            VelocityX = (isLeft ? 1 : -1) * BallSpeed * Math.Cos(angle);
            VelocityY = BallSpeed * Math.Sin(angle);
            (isLeft ? LeftTelemetry : RightTelemetry).Hits++;
            RallyHits++; LongestRally = Math.Max(LongestRally, RallyHits);
        }
        private static PaddleAction SafeAction(PaddleAction action)
        { return action == PaddleAction.Up || action == PaddleAction.Down ? action : PaddleAction.Stay; }
        private static double Move(double y, PaddleAction action)
        {
            y += (action == PaddleAction.Up ? -1 : action == PaddleAction.Down ? 1 : 0) * PaddleSpeed * DeltaSeconds;
            return Math.Max(PaddleHeight / 2, Math.Min(Height - PaddleHeight / 2, y));
        }
    }
}
