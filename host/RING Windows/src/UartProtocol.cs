using System;
using System.Globalization;

namespace PongExperiment
{
    public static class UartProtocol
    {
        public const int MaximumLineLength = 192;
        private static string Integer(double value)
        { return Math.Round(value, MidpointRounding.AwayFromZero).ToString("0", CultureInfo.InvariantCulture); }
        public static string Serialize(ControllerSnapshot s)
        {
            return String.Join(",", new[] { "STATE", "1", s.Tick.ToString(CultureInfo.InvariantCulture),
                s.Side == PaddleSide.Left ? "L" : "R", Integer(s.BallX), Integer(s.BallY),
                Integer(s.BallVelocityX), Integer(s.BallVelocityY), Integer(s.OwnPaddleY),
                Integer(s.OpponentPaddleY), Integer(s.FieldWidth), Integer(s.FieldHeight), Integer(s.PaddleHeight) }) + "\n";
        }
        public static bool TryParseAction(string line, long expectedTick, out PaddleAction action)
        {
            action = PaddleAction.Stay;
            if (line == null || line.Length > MaximumLineLength) return false;
            string[] parts = line.TrimEnd('\r', '\n').Split(',');
            long tick;
            if (parts.Length != 4 || parts[0] != "ACT" || parts[1] != "1" ||
                !Int64.TryParse(parts[2], NumberStyles.None, CultureInfo.InvariantCulture, out tick) ||
                tick != expectedTick || tick < 0) return false;
            switch (parts[3])
            {
                case "UP": action = PaddleAction.Up; return true;
                case "DOWN": action = PaddleAction.Down; return true;
                case "STAY": return true;
                default: return false;
            }
        }
    }
}
