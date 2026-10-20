using System;
using System.Diagnostics;
using System.Text;

// native_toolchain_c 0.19.5 decodes -utf8 output with the Windows system code page.
// Escape JSON Unicode characters so the original values survive either decoder.
class VswhereShim {
  static string Quote(string value) {
    if (value.Length > 0 && value.IndexOfAny(new[] {' ', '\t', '"'}) < 0) return value;
    var result = new StringBuilder("\"");
    int slashes = 0;
    foreach (char c in value) {
      if (c == '\\') { slashes++; continue; }
      result.Append('\\', c == '"' ? slashes * 2 + 1 : slashes);
      result.Append(c);
      slashes = 0;
    }
    result.Append('\\', slashes * 2);
    return result.Append('"').ToString();
  }
  static int Main(string[] args) {
    var arguments = new StringBuilder();
    bool utf8 = false, json = false;
    for (int i = 0; i < args.Length; i++) {
      if (i > 0) arguments.Append(' ');
      arguments.Append(Quote(args[i]));
      if (args[i] == "-utf8") utf8 = true;
      if (args[i] == "-format" && i + 1 < args.Length && args[i + 1] == "json") json = true;
    }
    string original = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86) +
      @"\Microsoft Visual Studio\Installer\vswhere.exe";
    var info = new ProcessStartInfo(original, arguments.ToString()) {
      UseShellExecute = false, CreateNoWindow = true,
      RedirectStandardOutput = true, RedirectStandardError = true,
      StandardOutputEncoding = utf8 ? Encoding.UTF8 : Encoding.Default,
      StandardErrorEncoding = utf8 ? Encoding.UTF8 : Encoding.Default
    };
    using (var process = Process.Start(info)) {
      string output = process.StandardOutput.ReadToEnd();
      string error = process.StandardError.ReadToEnd();
      process.WaitForExit();
      if (json) {
        var escaped = new StringBuilder();
        foreach (char c in output) {
          if (c > 127) escaped.Append("\\u").Append(((int)c).ToString("x4"));
          else escaped.Append(c);
        }
        output = escaped.ToString();
      }
      Console.Out.Write(output);
      Console.Error.Write(error);
      return process.ExitCode;
    }
  }
}
