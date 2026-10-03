using System;
using System.Collections.Generic;
using System.IO.Ports;
using System.Security;
using System.Text;
using Microsoft.Win32;

namespace PongExperiment
{
    public static class SerialPortCatalog
    {
        public static string Describe()
        {
            var details = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (string root in new[] { "USB", "FTDIBUS" }) {
                try {
                    using (RegistryKey key = Registry.LocalMachine.OpenSubKey("SYSTEM\\CurrentControlSet\\Enum\\" + root))
                        Inspect(key, details, 0, "");
                } catch (SecurityException) { } catch (UnauthorizedAccessException) { }
            }
            string[] ports = SerialPort.GetPortNames(); Array.Sort(ports, StringComparer.OrdinalIgnoreCase);
            var text = new StringBuilder("Available serial ports (manual selection; descriptions do not prove device identity):\r\n");
            foreach (string port in ports) {
                string detail; details.TryGetValue(port, out detail);
                text.AppendLine(port + "  " + (detail ?? "Description unavailable"));
            }
            if (ports.Length == 0) text.AppendLine("No serial ports enumerated.");
            return text.ToString();
        }
        private static void Inspect(RegistryKey key, Dictionary<string, string> details, int depth, string inherited)
        {
            if (key == null || depth > 3) return;
            string description = Convert.ToString(key.GetValue("FriendlyName") ?? key.GetValue("DeviceDesc"));
            var ids = key.GetValue("HardwareID") as string[];
            string info = description.Length == 0 ? inherited : description;
            if (ids != null) info += "  " + String.Join(" / ", ids);
            string port = key.GetValue("PortName") as string;
            if (port != null) details[port] = info;
            foreach (string child in key.GetSubKeyNames()) {
                try { using (RegistryKey next = key.OpenSubKey(child)) Inspect(next, details, depth + 1, info); }
                catch (SecurityException) { } catch (UnauthorizedAccessException) { }
            }
        }
    }
}
