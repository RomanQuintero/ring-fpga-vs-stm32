using System;
using System.IO;
using System.Text.RegularExpressions;

namespace PongExperiment
{
    public sealed class ControllerOptions
    {
        public bool FpgaSerial;
        public bool Stm32Serial = true;
        public string FpgaPort;
        public string Stm32Port = "COM4";
        public string VerificationDirectory;
        public bool ListPorts;
        public static string NormalizePort(string port)
        {
            if (port == null || !Regex.IsMatch(port, "^COM[1-9][0-9]*$", RegexOptions.IgnoreCase))
                throw new ArgumentException("Specify a port such as COM4 or COM5.");
            return port.ToUpperInvariant();
        }
        public static ControllerOptions Parse(string[] args)
        {
            var options = new ControllerOptions();
            for (int i = 0; i < args.Length; i++) {
                string key = args[i];
                if (key == "--list-ports") { options.ListPorts = true; continue; }
                if (++i >= args.Length) throw new ArgumentException("Missing value for " + key);
                string value = args[i];
                switch (key) {
                    case "--fpga-mode": options.FpgaSerial = SerialMode(value); break;
                    case "--stm32-mode": options.Stm32Serial = SerialMode(value); break;
                    case "--fpga-port": options.FpgaPort = NormalizePort(value); break;
                    case "--stm32-port": options.Stm32Port = NormalizePort(value); break;
                    case "--verify": options.VerificationDirectory = Path.GetFullPath(value); break;
                    default: throw new ArgumentException("Unknown argument: " + key);
                }
            }
            if (!options.ListPorts) {
                if (options.FpgaSerial && options.FpgaPort == null) throw new ArgumentException("FPGA serial mode requires --fpga-port COMx. Use --list-ports to inspect ports.");
                if (options.FpgaSerial && options.Stm32Serial && options.FpgaPort == options.Stm32Port)
                    throw new ArgumentException("FPGA and STM32 must use different serial ports.");
            }
            return options;
        }
        private static bool SerialMode(string mode)
        {
            if (mode == "serial") return true;
            if (mode == "simulated") return false;
            throw new ArgumentException("Mode must be simulated or serial.");
        }
    }
}
