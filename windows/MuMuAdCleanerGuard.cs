using System;
using System.IO;
using System.Text;
using System.Threading;

internal static class Program
{
    private static readonly UTF8Encoding Utf8NoBom = new UTF8Encoding(false);
    private static readonly string EmptyConfig = "{\n  \"info\": []\n}\n";

    private static int Main(string[] args)
    {
        string dataDir = null;
        string stateDir = null;

        for (int i = 0; i < args.Length - 1; i++)
        {
            if (string.Equals(args[i], "--data-dir", StringComparison.OrdinalIgnoreCase))
                dataDir = args[++i];
            else if (string.Equals(args[i], "--state-dir", StringComparison.OrdinalIgnoreCase))
                stateDir = args[++i];
        }

        if (string.IsNullOrWhiteSpace(dataDir) || string.IsNullOrWhiteSpace(stateDir))
            return 2;

        Directory.CreateDirectory(stateDir);
        string configPath = Path.Combine(dataDir, "imageManager.json");
        string stopPath = Path.Combine(stateDir, "guard.stop");

        while (!File.Exists(stopPath))
        {
            TryClearCampaign(configPath);
            Thread.Sleep(250);
        }

        return 0;
    }

    private static void TryClearCampaign(string path)
    {
        try
        {
            if (!File.Exists(path))
                return;

            string current;
            using (FileStream stream = new FileStream(
                path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (StreamReader reader = new StreamReader(stream, Encoding.UTF8, true))
            {
                current = reader.ReadToEnd();
            }

            if (!current.Contains("\"campaignId\"") &&
                !current.Contains("\"normalImageUrl\"") &&
                !current.Contains("\"hoverImageUrl\""))
                return;

            using (FileStream stream = new FileStream(
                path, FileMode.Create, FileAccess.Write, FileShare.Read))
            using (StreamWriter writer = new StreamWriter(stream, Utf8NoBom))
            {
                writer.Write(EmptyConfig);
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }
}
