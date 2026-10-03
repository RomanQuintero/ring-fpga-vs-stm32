using System;

namespace PongExperiment
{
    public enum PaddleAction { Stay, Up, Down }
    public enum PaddleSide { Left, Right }

    // Immutable information shared by every controller; positions use paddle centers.
    public sealed class ControllerSnapshot
    {
        public long Tick { get; private set; }
        public PaddleSide Side { get; private set; }
        public double BallX { get; private set; }
        public double BallY { get; private set; }
        public double BallVelocityX { get; private set; }
        public double BallVelocityY { get; private set; }
        public double OwnPaddleY { get; private set; }
        public double OpponentPaddleY { get; private set; }
        public double FieldWidth { get; private set; }
        public double FieldHeight { get; private set; }
        public double PaddleHeight { get; private set; }
        public ControllerSnapshot(long tick, PaddleSide side, double x, double y, double vx,
            double vy, double ownY, double opponentY, double width, double height, double paddleHeight)
        {
            Tick = tick; Side = side; BallX = x; BallY = y;
            BallVelocityX = vx; BallVelocityY = vy; OwnPaddleY = ownY;
            OpponentPaddleY = opponentY; FieldWidth = width; FieldHeight = height;
            PaddleHeight = paddleHeight;
        }
    }
    public interface IController
    {
        // Must return promptly. A future serial adapter handles transport on a worker
        // and returns its latest valid response, or Stay when a response is missing.
        PaddleAction Decide(ControllerSnapshot snapshot);
    }
    public sealed class SimulatedController : IController
    {
        public PaddleAction Decide(ControllerSnapshot snapshot)
        {
            double difference = snapshot.BallY - snapshot.OwnPaddleY;
            return difference < -6 ? PaddleAction.Up : difference > 6 ? PaddleAction.Down : PaddleAction.Stay;
        }
    }
}
