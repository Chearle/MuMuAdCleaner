using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Management;
using System.Reflection;
using System.Text;
using System.Web.Script.Serialization;

namespace MuMuAdCleanerHost
{
    public sealed class CleanupOptions
    {
        public IList<string> Roots { get; set; }
        public string DataDir { get; set; }
        public string StateDir { get; set; }
        public bool IncludeServices { get; set; }
        public bool InstallGuard { get; set; }
    }

    public sealed class CleanupState
    {
        public int Version { get; set; }
        public string AppliedAt { get; set; }
        public string StartupConfig { get; set; }
        public string StartupConfigBackup { get; set; }
        public List<RenamedFile> RenamedFiles { get; set; }
        public List<ServiceChange> Services { get; set; }

        public CleanupState()
        {
            RenamedFiles = new List<RenamedFile>();
            Services = new List<ServiceChange>();
        }
    }

    public sealed class RenamedFile
    {
        public string Source { get; set; }
        public string Backup { get; set; }
    }

    public sealed class ServiceChange
    {
        public string Name { get; set; }
        public string OriginalStartMode { get; set; }
    }

    public sealed class StatusInfo
    {
        public List<string> Roots { get; set; }
        public bool MuMuRunning { get; set; }
        public string StartupConfig { get; set; }
        public bool StartupConfigExists { get; set; }
        public bool CampaignPresent { get; set; }
        public int ActiveReporters { get; set; }
        public int DisabledReporters { get; set; }
        public bool GuardInstalled { get; set; }
        public bool CleanupStateExists { get; set; }
    }

    public static class HostCleaner
    {
        public const string Version = "1.1.0";
        public const string GuardTaskName = "MuMuAdCleanerStartupGuard";
        public const string BackupSuffix = ".adclean.bak";
        public const string GuardResourceName = "GuardPayload";

        private static readonly string[] ReporterNames =
        {
            "MuMuStatisticsReporter.exe",
            "MuMuPlayerCrashReporter.exe",
            "MuMuPlayerUpdater.exe",
            "MuMuPlayerUpdate.exe"
        };

        private static readonly UTF8Encoding Utf8NoBom = new UTF8Encoding(false);
        private static readonly JavaScriptSerializer Json = new JavaScriptSerializer();

        public static string DefaultStateDir
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MuMuAdCleanerHost"); }
        }

        public static string DefaultDataDir
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Netease", "MuMuPlayer", "data", "startupImage"); }
        }

        public static List<string> FindMuMuRoots(IEnumerable<string> preferredRoots = null)
        {
            var roots = new List<string>();
            if (preferredRoots != null)
            {
                foreach (string item in preferredRoots)
                {
                    if (String.IsNullOrWhiteSpace(item))
                    {
                        continue;
                    }
                    AddRootIfValid(roots, item);
                }
                return roots;
            }

            string[] bases =
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Netease"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Netease")
            };
            foreach (string baseDir in bases.Distinct(StringComparer.OrdinalIgnoreCase))
            {
                if (String.IsNullOrWhiteSpace(baseDir) || !Directory.Exists(baseDir))
                {
                    continue;
                }
                AddRootIfValid(roots, baseDir);
                try
                {
                    foreach (string level1 in Directory.EnumerateDirectories(baseDir))
                    {
                        AddRootIfValid(roots, level1);
                        try
                        {
                            foreach (string level2 in Directory.EnumerateDirectories(level1))
                            {
                                AddRootIfValid(roots, level2);
                            }
                        }
                        catch (UnauthorizedAccessException)
                        {
                        }
                        catch (IOException)
                        {
                        }
                    }
                }
                catch (UnauthorizedAccessException)
                {
                }
                catch (IOException)
                {
                }
            }
            return roots;
        }

        public static bool AddManualRoot(string path)
        {
            try
            {
                return IsMuMuRoot(Path.GetFullPath(path));
            }
            catch
            {
                return false;
            }
        }

        public static StatusInfo GetStatus(IEnumerable<string> roots = null, string dataDir = null, string stateDir = null)
        {
            List<string> foundRoots = FindMuMuRoots(roots);
            string resolvedDataDir = String.IsNullOrWhiteSpace(dataDir) ? DefaultDataDir : Path.GetFullPath(dataDir);
            string resolvedStateDir = String.IsNullOrWhiteSpace(stateDir) ? DefaultStateDir : Path.GetFullPath(stateDir);
            string configPath = Path.Combine(resolvedDataDir, "imageManager.json");

            var status = new StatusInfo
            {
                Roots = foundRoots,
                MuMuRunning = GetRunningMuMuProcesses().Count > 0,
                StartupConfig = configPath,
                StartupConfigExists = File.Exists(configPath),
                GuardInstalled = IsGuardInstalled(),
                CleanupStateExists = File.Exists(Path.Combine(resolvedStateDir, "state.json"))
            };

            if (status.StartupConfigExists)
            {
                try
                {
                    string raw = File.ReadAllText(configPath, Encoding.UTF8);
                    status.CampaignPresent = ContainsCampaign(raw);
                }
                catch
                {
                }
            }

            foreach (string root in foundRoots)
            {
                status.ActiveReporters += CountReporterFiles(root, false);
                status.DisabledReporters += CountReporterFiles(root, true);
            }
            return status;
        }

        public static bool MuMuIsRunning()
        {
            return GetRunningMuMuProcesses().Count > 0;
        }

        public static void StopMuMuProcesses(Action<string> log = null)
        {
            List<Process> processes = GetRunningMuMuProcesses();
            foreach (Process process in processes)
            {
                try
                {
                    if (log != null)
                    {
                        log("停止进程 " + process.ProcessName);
                    }
                    process.Kill();
                    process.WaitForExit(5000);
                }
                catch
                {
                }
                finally
                {
                    process.Dispose();
                }
            }
            System.Threading.Thread.Sleep(1200);
        }

        public static CleanupState Apply(CleanupOptions options, Action<string> log = null)
        {
            if (options == null)
            {
                throw new ArgumentNullException("options");
            }
            List<string> roots = FindMuMuRoots(options.Roots);
            if (roots.Count == 0)
            {
                throw new InvalidOperationException("没有找到 MuMu 安装目录，请先选择正确的目录。");
            }
            if (MuMuIsRunning())
            {
                throw new InvalidOperationException("MuMu 仍在运行，请先关闭模拟器。");
            }

            string stateDir = EnsureStateDir(options.StateDir);
            string dataDir = EnsureDirectory(String.IsNullOrWhiteSpace(options.DataDir) ? DefaultDataDir : options.DataDir);
            string stateFile = Path.Combine(stateDir, "state.json");
            CleanupState state = LoadState(stateFile) ?? new CleanupState();
            state.Version = 2;
            state.AppliedAt = DateTimeOffset.Now.ToString("o");

            ApplyReporterChanges(state, roots, log);
            ApplyStartupConfig(state, Path.Combine(dataDir, "imageManager.json"), log);
            if (options.IncludeServices)
            {
                ApplyServiceChanges(state, roots, log);
            }
            SaveState(stateFile, state);

            if (options.InstallGuard)
            {
                InstallGuard(stateDir, dataDir, log);
            }
            if (log != null)
            {
                log("Windows 主机端清理完成。");
            }
            return state;
        }

        public static void Restore(string stateDir = null, Action<string> log = null)
        {
            string resolvedStateDir = EnsureStateDir(stateDir);
            string stateFile = Path.Combine(resolvedStateDir, "state.json");
            CleanupState state = LoadState(stateFile);
            if (state == null)
            {
                throw new InvalidOperationException("没有找到清理记录，可能尚未执行过清理。");
            }
            if (MuMuIsRunning())
            {
                throw new InvalidOperationException("MuMu 仍在运行，请先关闭模拟器。");
            }

            RemoveGuard(resolvedStateDir, log);
            RestoreServiceChanges(state, log);
            RestoreReporterChanges(state, log);
            RestoreStartupConfig(state, log);
            File.Delete(stateFile);
            if (log != null)
            {
                log("MuMu Windows 主机端已恢复原状。");
            }
        }

        private static void AddRootIfValid(List<string> roots, string path)
        {
            try
            {
                string fullPath = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar);
                if (IsMuMuRoot(fullPath) && !roots.Contains(fullPath, StringComparer.OrdinalIgnoreCase))
                {
                    roots.Add(fullPath);
                }
            }
            catch
            {
            }
        }

        private static bool IsMuMuRoot(string path)
        {
            return Directory.Exists(path) &&
                (File.Exists(Path.Combine(path, "shell", "MuMuPlayer.exe")) ||
                 File.Exists(Path.Combine(path, "nx_main", "MuMuNxMain.exe")) ||
                 Directory.Exists(Path.Combine(path, "nx_device")));
        }

        private static List<Process> GetRunningMuMuProcesses()
        {
            var result = new List<Process>();
            HashSet<string> names = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "MuMuPlayer",
                "MuMuNxMain",
                "MuMuNxDevice",
                "mumunxdevice",
                "MuMuVMMHeadless",
                "MuMuPlayerService"
            };
            foreach (Process process in Process.GetProcesses())
            {
                try
                {
                    if (names.Contains(process.ProcessName))
                    {
                        result.Add(process);
                    }
                    else
                    {
                        process.Dispose();
                    }
                }
                catch
                {
                    process.Dispose();
                }
            }
            return result;
        }

        private static int CountReporterFiles(string root, bool disabled)
        {
            int count = 0;
            foreach (string name in ReporterNames)
            {
                string pattern = disabled ? name + BackupSuffix : name;
                count += EnumerateFiles(root, pattern).Count();
            }
            return count;
        }

        private static IEnumerable<string> EnumerateFiles(string root, string fileName)
        {
            var pending = new Stack<string>();
            pending.Push(root);
            while (pending.Count > 0)
            {
                string current = pending.Pop();
                string direct = Path.Combine(current, fileName);
                if (File.Exists(direct))
                {
                    yield return direct;
                }
                try
                {
                    foreach (string child in Directory.EnumerateDirectories(current))
                    {
                        pending.Push(child);
                    }
                }
                catch (UnauthorizedAccessException)
                {
                }
                catch (IOException)
                {
                }
            }
        }

        private static void ApplyReporterChanges(CleanupState state, IList<string> roots, Action<string> log)
        {
            var existingBySource = state.RenamedFiles.ToDictionary(
                item => item.Source,
                item => item,
                StringComparer.OrdinalIgnoreCase
            );

            foreach (string root in roots)
            {
                foreach (string name in ReporterNames)
                {
                    foreach (string source in EnumerateFiles(root, name).ToList())
                    {
                        RenamedFile previous;
                        if (existingBySource.TryGetValue(source, out previous) &&
                            File.Exists(previous.Backup) &&
                            !File.Exists(source))
                        {
                            continue;
                        }

                        string backup = source + BackupSuffix;
                        if (File.Exists(backup))
                        {
                            backup = source + ".adclean-" + DateTime.Now.ToString("yyyyMMddHHmmssfff") + ".bak";
                        }
                        File.Move(source, backup);
                        var change = new RenamedFile { Source = source, Backup = backup };
                        state.RenamedFiles.Add(change);
                        existingBySource[source] = change;
                        if (log != null)
                        {
                            log("已改名：" + Path.GetFileName(source) + " → " + Path.GetFileName(backup));
                        }
                    }
                }
            }
        }

        private static void ApplyStartupConfig(CleanupState state, string configPath, Action<string> log)
        {
            if (!File.Exists(configPath))
            {
                state.StartupConfig = null;
                state.StartupConfigBackup = null;
                if (log != null)
                {
                    log("尚未发现启动广告配置，守护进程会在配置出现后处理。");
                }
                return;
            }

            string backup = state.StartupConfigBackup;
            if (String.IsNullOrWhiteSpace(backup) || !File.Exists(backup))
            {
                backup = Path.Combine(Path.GetDirectoryName(configPath), "imageManager.adclean-original.json");
            }
            if (!File.Exists(backup))
            {
                File.Copy(configPath, backup);
                if (log != null)
                {
                    log("已备份原始启动广告配置。");
                }
            }

            File.WriteAllText(configPath, "{\n  \"info\": []\n}\n", Utf8NoBom);
            state.StartupConfig = configPath;
            state.StartupConfigBackup = backup;
            if (log != null)
            {
                log("已清空启动广告配置。");
            }
        }

        private static void RestoreReporterChanges(CleanupState state, Action<string> log)
        {
            foreach (RenamedFile item in state.RenamedFiles)
            {
                try
                {
                    if (File.Exists(item.Backup) && !File.Exists(item.Source))
                    {
                        File.Move(item.Backup, item.Source);
                        if (log != null)
                        {
                            log("已恢复：" + Path.GetFileName(item.Source));
                        }
                    }
                }
                catch (Exception ex)
                {
                    if (log != null)
                    {
                        log("恢复失败：" + Path.GetFileName(item.Source) + " (" + ex.Message + ")");
                    }
                }
            }
        }

        private static void RestoreStartupConfig(CleanupState state, Action<string> log)
        {
            if (!String.IsNullOrWhiteSpace(state.StartupConfigBackup) &&
                File.Exists(state.StartupConfigBackup) &&
                !String.IsNullOrWhiteSpace(state.StartupConfig))
            {
                Directory.CreateDirectory(Path.GetDirectoryName(state.StartupConfig));
                File.Copy(state.StartupConfigBackup, state.StartupConfig, true);
                if (log != null)
                {
                    log("已恢复原始启动广告配置。");
                }
            }
        }

        private static void ApplyServiceChanges(CleanupState state, IList<string> roots, Action<string> log)
        {
            var existing = new HashSet<string>(state.Services.Select(item => item.Name), StringComparer.OrdinalIgnoreCase);
            foreach (ServiceInfo service in FindMuMuServices(roots))
            {
                if (existing.Contains(service.Name))
                {
                    continue;
                }
                state.Services.Add(new ServiceChange { Name = service.Name, OriginalStartMode = service.StartMode });
                SetService(service.Name, "Manual", true);
                if (log != null)
                {
                    log("已停止服务：" + service.Name);
                }
            }
        }

        private static void RestoreServiceChanges(CleanupState state, Action<string> log)
        {
            foreach (ServiceChange service in state.Services)
            {
                try
                {
                    SetService(service.Name, service.OriginalStartMode, false);
                    if (log != null)
                    {
                        log("已恢复服务：" + service.Name + " (" + service.OriginalStartMode + ")");
                    }
                }
                catch (Exception ex)
                {
                    if (log != null)
                    {
                        log("恢复服务失败：" + service.Name + " (" + ex.Message + ")");
                    }
                }
            }
        }

        private sealed class ServiceInfo
        {
            public string Name { get; set; }
            public string PathName { get; set; }
            public string StartMode { get; set; }
        }

        private static List<ServiceInfo> FindMuMuServices(IEnumerable<string> roots)
        {
            var result = new List<ServiceInfo>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                using (var searcher = new ManagementObjectSearcher(
                    "SELECT Name, DisplayName, PathName, StartMode FROM Win32_Service"))
                using (ManagementObjectCollection services = searcher.Get())
                {
                    foreach (ManagementBaseObject item in services)
                    {
                        using (item)
                        {
                            string name = Convert.ToString(item["Name"]);
                            string displayName = Convert.ToString(item["DisplayName"]);
                            string path = Convert.ToString(item["PathName"]);
                            bool byName = (name ?? "").IndexOf("MuMu", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                (name ?? "").IndexOf("Nemu", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                (name ?? "").IndexOf("Netease", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                (displayName ?? "").IndexOf("MuMu", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                (displayName ?? "").IndexOf("Nemu", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                (displayName ?? "").IndexOf("Netease", StringComparison.OrdinalIgnoreCase) >= 0;
                            bool byPath = roots.Any(root =>
                                !String.IsNullOrWhiteSpace(path) &&
                                path.IndexOf(root, StringComparison.OrdinalIgnoreCase) >= 0);
                            if ((byName || byPath) && seen.Add(name))
                            {
                                result.Add(new ServiceInfo
                                {
                                    Name = name,
                                    PathName = path,
                                    StartMode = Convert.ToString(item["StartMode"])
                                });
                            }
                        }
                    }
                }
            }
            catch
            {
            }
            return result;
        }

        private static void SetService(string name, string startMode, bool stop)
        {
            string escaped = (name ?? "").Replace("'", "''");
            using (var searcher = new ManagementObjectSearcher(
                "SELECT Name FROM Win32_Service WHERE Name='" + escaped + "'"))
            using (ManagementObjectCollection services = searcher.Get())
            {
                foreach (ManagementObject item in services)
                {
                    using (item)
                    {
                        ManagementBaseObject input = item.GetMethodParameters("Change");
                        input["StartMode"] = startMode;
                        ManagementBaseObject output = item.InvokeMethod("Change", input, null);
                        uint code = Convert.ToUInt32(output["ReturnValue"]);
                        output.Dispose();
                        input.Dispose();
                        if (code != 0)
                        {
                            throw new InvalidOperationException("服务修改返回代码 " + code);
                        }

                        if (stop)
                        {
                            ManagementBaseObject stopOutput = item.InvokeMethod("StopService", null, null);
                            stopOutput.Dispose();
                        }
                    }
                }
            }
        }

        private static bool ContainsCampaign(string raw)
        {
            return (raw ?? "").IndexOf("\"campaignId\"", StringComparison.Ordinal) >= 0 ||
                (raw ?? "").IndexOf("\"normalImageUrl\"", StringComparison.Ordinal) >= 0 ||
                (raw ?? "").IndexOf("\"hoverImageUrl\"", StringComparison.Ordinal) >= 0;
        }

        private static string EnsureStateDir(string stateDir)
        {
            string resolved = EnsureDirectory(String.IsNullOrWhiteSpace(stateDir) ? DefaultStateDir : stateDir);
            return resolved;
        }

        private static string EnsureDirectory(string path)
        {
            string resolved = Path.GetFullPath(path);
            Directory.CreateDirectory(resolved);
            return resolved;
        }

        private static CleanupState LoadState(string stateFile)
        {
            if (!File.Exists(stateFile))
            {
                return null;
            }
            string raw = File.ReadAllText(stateFile, Encoding.UTF8);
            CleanupState state = Json.Deserialize<CleanupState>(raw);
            if (state.RenamedFiles == null)
            {
                state.RenamedFiles = new List<RenamedFile>();
            }
            if (state.Services == null)
            {
                state.Services = new List<ServiceChange>();
            }
            return state;
        }

        private static void SaveState(string stateFile, CleanupState state)
        {
            File.WriteAllText(stateFile, Json.Serialize(state), Utf8NoBom);
        }

        private static void InstallGuard(string stateDir, string dataDir, Action<string> log)
        {
            string guardPath = Path.Combine(stateDir, "MuMuAdCleanerGuard.exe");
            StopGuardProcesses(stateDir);
            if (File.Exists(guardPath))
            {
                File.Delete(guardPath);
            }

            Assembly assembly = Assembly.GetExecutingAssembly();
            using (Stream input = assembly.GetManifestResourceStream(GuardResourceName))
            {
                if (input == null)
                {
                    throw new InvalidOperationException("内置守护程序缺失。");
                }
                using (FileStream output = new FileStream(guardPath, FileMode.Create, FileAccess.Write, FileShare.None))
                {
                    input.CopyTo(output);
                }
            }

            string stopFile = Path.Combine(stateDir, "guard.stop");
            if (File.Exists(stopFile))
            {
                File.Delete(stopFile);
            }

            string xmlPath = Path.Combine(stateDir, "guard-task.xml");
            string identity = System.Security.Principal.WindowsIdentity.GetCurrent().Name;
            string arguments = "--guard --data-dir \"" + dataDir + "\" --state-dir \"" + stateDir + "\"";
            string xml = BuildTaskXml(identity, guardPath, arguments);
            File.WriteAllText(xmlPath, xml, Encoding.Unicode);
            ProcessResult result = RunProcess(
                Path.Combine(Environment.SystemDirectory, "schtasks.exe"),
                "/Create /TN \"" + GuardTaskName + "\" /XML \"" + xmlPath + "\" /F"
            );
            File.Delete(xmlPath);
            if (result.ExitCode != 0)
            {
                throw new InvalidOperationException("安装开机守护失败：" + result.Output);
            }
            RunProcess(Path.Combine(Environment.SystemDirectory, "schtasks.exe"), "/Run /TN \"" + GuardTaskName + "\"");
            if (log != null)
            {
                log("已安装并启动开机守护。");
            }
        }

        private static string BuildTaskXml(string identity, string executable, string arguments)
        {
            string user = System.Security.SecurityElement.Escape(identity);
            string exe = System.Security.SecurityElement.Escape(executable);
            string args = System.Security.SecurityElement.Escape(arguments);
            return "<?xml version=\"1.0\" encoding=\"UTF-16\"?>\n" +
                "<Task version=\"1.4\" xmlns=\"http://schemas.microsoft.com/windows/2004/02/mit/task\">\n" +
                "  <RegistrationInfo><Description>MuMuAdCleaner startup campaign guard</Description></RegistrationInfo>\n" +
                "  <Triggers><LogonTrigger><Enabled>true</Enabled><UserId>" + user + "</UserId></LogonTrigger></Triggers>\n" +
                "  <Principals><Principal id=\"Author\"><UserId>" + user + "</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>\n" +
                "  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>true</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable><ExecutionTimeLimit>PT0S</ExecutionTimeLimit></Settings>\n" +
                "  <Actions Context=\"Author\"><Exec><Command>" + exe + "</Command><Arguments>" + args + "</Arguments></Exec></Actions>\n" +
                "</Task>";
        }

        public static bool IsGuardInstalled()
        {
            ProcessResult result = RunProcess(
                Path.Combine(Environment.SystemDirectory, "schtasks.exe"),
                "/Query /TN \"" + GuardTaskName + "\""
            );
            return result.ExitCode == 0;
        }

        private static void RemoveGuard(string stateDir, Action<string> log)
        {
            StopGuardProcesses(stateDir);
            string schtasks = Path.Combine(Environment.SystemDirectory, "schtasks.exe");
            RunProcess(schtasks, "/Delete /TN \"" + GuardTaskName + "\" /F");
            string stopFile = Path.Combine(stateDir, "guard.stop");
            try
            {
                File.Delete(stopFile);
            }
            catch
            {
            }
            if (log != null)
            {
                log("已停止并移除开机守护。");
            }
        }

        private static void StopGuardProcesses(string stateDir)
        {
            string stopFile = Path.Combine(stateDir, "guard.stop");
            File.WriteAllText(stopFile, "stop", Utf8NoBom);
            string schtasks = Path.Combine(Environment.SystemDirectory, "schtasks.exe");
            RunProcess(schtasks, "/End /TN \"" + GuardTaskName + "\"");
            foreach (Process process in Process.GetProcessesByName("MuMuAdCleanerGuard"))
            {
                try
                {
                    process.Kill();
                    process.WaitForExit(3000);
                }
                catch
                {
                }
                finally
                {
                    process.Dispose();
                }
            }
            System.Threading.Thread.Sleep(500);
        }

        private sealed class ProcessResult
        {
            public int ExitCode { get; set; }
            public string Output { get; set; }
        }

        private static ProcessResult RunProcess(string fileName, string arguments)
        {
            try
            {
                var start = new ProcessStartInfo
                {
                    FileName = fileName,
                    Arguments = arguments,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                using (Process process = Process.Start(start))
                {
                    string stdout = process.StandardOutput.ReadToEnd();
                    string stderr = process.StandardError.ReadToEnd();
                    process.WaitForExit();
                    return new ProcessResult
                    {
                        ExitCode = process.ExitCode,
                        Output = (stdout + "\n" + stderr).Trim()
                    };
                }
            }
            catch (Exception ex)
            {
                return new ProcessResult { ExitCode = -1, Output = ex.Message };
            }
        }

        public static int RunGuard(string[] args)
        {
            string dataDir = null;
            string stateDir = null;
            for (int i = 0; i < args.Length - 1; i++)
            {
                if (String.Equals(args[i], "--data-dir", StringComparison.OrdinalIgnoreCase))
                {
                    dataDir = args[++i];
                }
                else if (String.Equals(args[i], "--state-dir", StringComparison.OrdinalIgnoreCase))
                {
                    stateDir = args[++i];
                }
            }
            if (String.IsNullOrWhiteSpace(dataDir) || String.IsNullOrWhiteSpace(stateDir))
            {
                return 2;
            }

            Directory.CreateDirectory(stateDir);
            string configPath = Path.Combine(dataDir, "imageManager.json");
            string stopPath = Path.Combine(stateDir, "guard.stop");
            while (!File.Exists(stopPath))
            {
                TryClearCampaign(configPath);
                System.Threading.Thread.Sleep(250);
            }
            return 0;
        }

        private static void TryClearCampaign(string path)
        {
            try
            {
                if (!File.Exists(path))
                {
                    return;
                }
                string current;
                using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (var reader = new StreamReader(stream, Encoding.UTF8, true))
                {
                    current = reader.ReadToEnd();
                }
                if (!ContainsCampaign(current))
                {
                    return;
                }
                using (var stream = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.Read))
                using (var writer = new StreamWriter(stream, Utf8NoBom))
                {
                    writer.Write("{\n  \"info\": []\n}\n");
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
}
