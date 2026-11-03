using System;
using System.IO;
using System.Linq;
using MuMuAdCleanerHost;

internal static class MuMuHostCoreTest
{
    private static void Assert(bool condition, string message)
    {
        if (!condition)
        {
            throw new Exception("Assertion failed: " + message);
        }
    }

    private static int Main(string[] args)
    {
        try
        {
            return Run(args);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex.GetType().FullName + ": " + ex.Message);
            Console.Error.WriteLine(ex.StackTrace);
            return 1;
        }
    }

    private static int Run(string[] args)
    {
        if (args.Length != 4)
        {
            Console.Error.WriteLine("usage: MuMuHostCoreTest <root> <data> <state> <install-guard>");
            return 2;
        }

        string root = Path.GetFullPath(args[0]);
        string dataDir = Path.GetFullPath(args[1]);
        string stateDir = Path.GetFullPath(args[2]);
        bool installGuard = String.Equals(args[3], "1", StringComparison.Ordinal);
        Directory.CreateDirectory(Path.Combine(root, "shell"));
        Directory.CreateDirectory(Path.Combine(root, "nx_main"));
        Directory.CreateDirectory(Path.Combine(root, "bin"));
        Directory.CreateDirectory(dataDir);
        File.WriteAllText(Path.Combine(root, "shell", "MuMuPlayer.exe"), "shell");
        File.WriteAllText(Path.Combine(root, "nx_main", "MuMuNxMain.exe"), "main");
        string reporter = Path.Combine(root, "bin", "MuMuPlayerUpdater.exe");
        string config = Path.Combine(dataDir, "imageManager.json");
        string original = "{\"info\":[{\"campaignId\":\"abc\"}]}";
        File.WriteAllText(reporter, "updater");
        File.WriteAllText(config, original);

        Assert(HostCleaner.AddManualRoot(root), "fixture should be recognized");
        Assert(HostCleaner.FindMuMuRoots(new[] { root }).Count == 1, "root discovery should work");

        HostCleaner.Apply(new CleanupOptions
        {
            Roots = new[] { root },
            DataDir = dataDir,
            StateDir = stateDir,
            InstallGuard = installGuard
        }, Console.WriteLine);
        if (installGuard)
        {
            Assert(HostCleaner.IsGuardInstalled(), "guard task should be installed");
        }

        Assert(!File.Exists(reporter), "active updater should be renamed");
        Assert(File.Exists(reporter + HostCleaner.BackupSuffix), "updater backup should exist");
        Assert(File.ReadAllText(config).IndexOf("campaignId", StringComparison.Ordinal) < 0,
            "campaign config should be cleared");
        Assert(HostCleaner.GetStatus(new[] { root }, dataDir, stateDir).CleanupStateExists,
            "cleanup state should be present");

        File.WriteAllText(config, "{\"info\":[{\"campaignId\":\"second\"}]}");
        HostCleaner.Apply(new CleanupOptions
        {
            Roots = new[] { root },
            DataDir = dataDir,
            StateDir = stateDir,
            InstallGuard = installGuard
        }, Console.WriteLine);
        string originalBackup = File.ReadAllText(
            Path.Combine(dataDir, "imageManager.adclean-original.json"));
        Assert(originalBackup == original, "repeated apply must preserve the original backup");

        HostCleaner.Restore(stateDir, Console.WriteLine);
        Assert(File.Exists(reporter), "updater should be restored");
        Assert(File.ReadAllText(config) == original, "startup config should be restored");
        Assert(!File.Exists(Path.Combine(stateDir, "state.json")), "state should be removed");
        if (installGuard)
        {
            Assert(!HostCleaner.IsGuardInstalled(), "guard task should be removed");
        }

        Console.WriteLine("MuMuHostCore tests passed.");
        return 0;
    }
}
