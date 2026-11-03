using System;
using System.Drawing;
using System.Linq;
using System.Threading;
using System.Windows.Forms;

namespace MuMuAdCleanerHost
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            if (args.Length > 0 && String.Equals(args[0], "--guard", StringComparison.OrdinalIgnoreCase))
            {
                return HostCleaner.RunGuard(args);
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
            return 0;
        }
    }

    internal sealed class MainForm : Form
    {
        private readonly string dataDir = HostCleaner.DefaultDataDir;
        private readonly string stateDir = HostCleaner.DefaultStateDir;
        private string manualRoot;

        private readonly Label installValue = new Label();
        private readonly Label stateValue = new Label();
        private readonly Label guardValue = new Label();
        private readonly TextBox logBox = new TextBox();
        private readonly Button applyButton = new Button();
        private readonly Button restoreButton = new Button();
        private readonly Button refreshButton = new Button();
        private readonly Button browseButton = new Button();
        private readonly CheckBox guardCheck = new CheckBox();
        private readonly CheckBox serviceCheck = new CheckBox();
        private readonly Label banner = new Label();

        public MainForm()
        {
            Text = "MuMu 广告清理 " + HostCleaner.Version;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(780, 590);
            MinimumSize = new Size(720, 540);
            BackColor = Color.FromArgb(247, 248, 251);
            Font = new Font("Microsoft YaHei UI", 9F);
            Icon = SystemIcons.Shield;
            BuildUi();
            Shown += delegate { RefreshStatus(); };
        }

        private void BuildUi()
        {
            var header = new Panel
            {
                Dock = DockStyle.Top,
                Height = 108,
                BackColor = Color.FromArgb(24, 32, 46),
                Padding = new Padding(28, 20, 28, 12)
            };
            var title = new Label
            {
                Text = "MuMu 广告清理",
                AutoSize = true,
                ForeColor = Color.White,
                Font = new Font("Microsoft YaHei UI", 21F, FontStyle.Bold),
                Location = new Point(28, 18)
            };
            var subtitle = new Label
            {
                Text = "Windows 主机端 · 双击操作，无需命令行 · 可完整恢复",
                AutoSize = true,
                ForeColor = Color.FromArgb(190, 202, 220),
                Font = new Font("Microsoft YaHei UI", 9.5F),
                Location = new Point(31, 66)
            };
            header.Controls.Add(title);
            header.Controls.Add(subtitle);
            Controls.Add(header);

            var infoCard = new Panel
            {
                Location = new Point(28, 130),
                Size = new Size(724, 142),
                Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right,
                BackColor = Color.White,
                Padding = new Padding(18)
            };
            Controls.Add(infoCard);
            infoCard.BringToFront();

            var statusTitle = new Label
            {
                Text = "当前状态",
                AutoSize = true,
                ForeColor = Color.FromArgb(65, 76, 94),
                Font = new Font("Microsoft YaHei UI", 10F, FontStyle.Bold),
                Location = new Point(18, 14)
            };
            infoCard.Controls.Add(statusTitle);
            AddInfoRow(infoCard, "MuMu 安装", installValue, 46);
            AddInfoRow(infoCard, "广告状态", stateValue, 72);
            AddInfoRow(infoCard, "后台守护", guardValue, 98);

            browseButton.Text = "选择目录";
            browseButton.SetBounds(610, 43, 94, 28);
            browseButton.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            browseButton.FlatStyle = FlatStyle.Flat;
            browseButton.FlatAppearance.BorderColor = Color.FromArgb(198, 207, 220);
            browseButton.BackColor = Color.White;
            browseButton.Cursor = Cursors.Hand;
            browseButton.Click += delegate { BrowseRoot(); };
            infoCard.Controls.Add(browseButton);

            banner.Text = HostCleaner.Version == null ? "" : "建议关闭 MuMu 后执行；清理会备份原始文件，可随时恢复。";
            banner.SetBounds(28, 286, 724, 24);
            banner.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            banner.ForeColor = Color.FromArgb(86, 99, 119);
            Controls.Add(banner);
            banner.BringToFront();

            guardCheck.Text = "安装开机守护（推荐）";
            guardCheck.Checked = true;
            guardCheck.SetBounds(28, 316, 260, 24);
            guardCheck.ForeColor = Color.FromArgb(50, 61, 79);
            Controls.Add(guardCheck);
            guardCheck.BringToFront();

            serviceCheck.Text = "同时停止 MuMu 后台服务（可选）";
            serviceCheck.SetBounds(300, 316, 300, 24);
            serviceCheck.ForeColor = Color.FromArgb(50, 61, 79);
            Controls.Add(serviceCheck);
            serviceCheck.BringToFront();

            applyButton.Text = "一键清理广告";
            applyButton.SetBounds(28, 352, 224, 52);
            applyButton.BackColor = Color.FromArgb(42, 112, 235);
            applyButton.ForeColor = Color.White;
            applyButton.FlatStyle = FlatStyle.Flat;
            applyButton.FlatAppearance.BorderSize = 0;
            applyButton.Font = new Font("Microsoft YaHei UI", 11F, FontStyle.Bold);
            applyButton.Cursor = Cursors.Hand;
            applyButton.Click += delegate { ApplyCleanup(); };
            Controls.Add(applyButton);
            applyButton.BringToFront();

            restoreButton.Text = "恢复原状";
            restoreButton.SetBounds(264, 352, 170, 52);
            restoreButton.BackColor = Color.White;
            restoreButton.ForeColor = Color.FromArgb(56, 68, 87);
            restoreButton.FlatStyle = FlatStyle.Flat;
            restoreButton.FlatAppearance.BorderColor = Color.FromArgb(195, 204, 218);
            restoreButton.Cursor = Cursors.Hand;
            restoreButton.Click += delegate { RestoreCleanup(); };
            Controls.Add(restoreButton);
            restoreButton.BringToFront();

            refreshButton.Text = "刷新状态";
            refreshButton.SetBounds(446, 352, 118, 52);
            refreshButton.BackColor = Color.White;
            refreshButton.ForeColor = Color.FromArgb(56, 68, 87);
            refreshButton.FlatStyle = FlatStyle.Flat;
            refreshButton.FlatAppearance.BorderColor = Color.FromArgb(195, 204, 218);
            refreshButton.Cursor = Cursors.Hand;
            refreshButton.Click += delegate { RefreshStatus(); };
            Controls.Add(refreshButton);
            refreshButton.BringToFront();

            var logTitle = new Label
            {
                Text = "运行日志",
                AutoSize = true,
                ForeColor = Color.FromArgb(65, 76, 94),
                Font = new Font("Microsoft YaHei UI", 9.5F, FontStyle.Bold),
                Location = new Point(30, 420)
            };
            Controls.Add(logTitle);
            logTitle.BringToFront();

            logBox.SetBounds(28, 446, 724, 122);
            logBox.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom;
            logBox.Multiline = true;
            logBox.ReadOnly = true;
            logBox.ScrollBars = ScrollBars.Vertical;
            logBox.BackColor = Color.White;
            logBox.ForeColor = Color.FromArgb(59, 70, 88);
            logBox.BorderStyle = BorderStyle.FixedSingle;
            logBox.Font = new Font("Consolas", 9F);
            Controls.Add(logBox);
            logBox.BringToFront();
        }

        private static void AddInfoRow(Control parent, string caption, Label value, int top)
        {
            var label = new Label
            {
                Text = caption,
                AutoSize = true,
                ForeColor = Color.FromArgb(117, 129, 146),
                Location = new Point(18, top)
            };
            value.AutoSize = true;
            value.MaximumSize = new Size(540, 20);
            value.AutoEllipsis = true;
            value.ForeColor = Color.FromArgb(44, 55, 73);
            value.Location = new Point(92, top);
            parent.Controls.Add(label);
            parent.Controls.Add(value);
        }

        private void BrowseRoot()
        {
            using (var dialog = new FolderBrowserDialog())
            {
                dialog.Description = "选择包含 shell、nx_main 或 nx_device 的 MuMu 安装目录";
                dialog.ShowNewFolderButton = false;
                if (dialog.ShowDialog(this) == DialogResult.OK)
                {
                    if (!HostCleaner.AddManualRoot(dialog.SelectedPath))
                    {
                        MessageBox.Show(this, "该目录不像 MuMu 安装目录。请选择包含 shell、nx_main 或 nx_device 的目录。",
                            "目录不正确", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        return;
                    }
                    manualRoot = dialog.SelectedPath;
                    RefreshStatus();
                }
            }
        }

        private string[] CurrentRoots()
        {
            return String.IsNullOrWhiteSpace(manualRoot) ? null : new[] { manualRoot };
        }

        private void RefreshStatus()
        {
            try
            {
                StatusInfo status = HostCleaner.GetStatus(CurrentRoots(), dataDir, stateDir);
                if (status.Roots.Count == 0)
                {
                    installValue.Text = "未找到，请点击“选择目录”";
                    installValue.ForeColor = Color.FromArgb(190, 99, 42);
                }
                else
                {
                    installValue.Text = status.Roots[0] +
                        (status.Roots.Count > 1 ? " 等 " + status.Roots.Count + " 个目录" : "");
                    installValue.ForeColor = Color.FromArgb(44, 55, 73);
                }

                if (status.CampaignPresent)
                {
                    stateValue.Text = "检测到启动广告配置";
                    stateValue.ForeColor = Color.FromArgb(190, 99, 42);
                }
                else if (status.DisabledReporters > 0 || status.CleanupStateExists || status.GuardInstalled)
                {
                    stateValue.Text = "已清理或部分清理";
                    stateValue.ForeColor = Color.FromArgb(31, 132, 90);
                }
                else
                {
                    stateValue.Text = "未清理";
                    stateValue.ForeColor = Color.FromArgb(44, 55, 73);
                }

                guardValue.Text = status.GuardInstalled ? "已安装" : "未安装";
                guardValue.ForeColor = status.GuardInstalled
                    ? Color.FromArgb(31, 132, 90)
                    : Color.FromArgb(44, 55, 73);
                restoreButton.Enabled = status.CleanupStateExists;
            }
            catch (Exception ex)
            {
                AppendLog("状态检查失败：" + ex.Message);
            }
        }

        private void ApplyCleanup()
        {
            string[] roots = CurrentRoots();
            if (roots == null)
            {
                roots = HostCleaner.FindMuMuRoots().ToArray();
            }
            if (roots.Length == 0)
            {
                MessageBox.Show(this, "没有找到 MuMu。请先选择 MuMu 安装目录。",
                    "未找到 MuMu", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                BrowseRoot();
                return;
            }

            if (!ConfirmMuMuClosed()) return;
            string summary = "将清理 Windows 主机端开屏广告，并处理更新、统计和崩溃上报程序。";
            if (guardCheck.Checked) summary += "\n\n会安装当前用户的登录守护，用于拦截重新下载的广告配置。";
            if (serviceCheck.Checked) summary += "\n\n会停止并调整 MuMu 相关后台服务。";
            summary += "\n\n原始文件会备份，可通过“恢复原状”还原。";
            if (MessageBox.Show(this, summary, "确认清理", MessageBoxButtons.OKCancel,
                MessageBoxIcon.Information) != DialogResult.OK)
            {
                return;
            }

            RunOperation("正在清理…", delegate
            {
                HostCleaner.Apply(new CleanupOptions
                {
                    Roots = roots,
                    DataDir = dataDir,
                    StateDir = stateDir,
                    IncludeServices = serviceCheck.Checked,
                    InstallGuard = guardCheck.Checked
                }, AppendLogFromWorker);
            }, "清理完成");
        }

        private void RestoreCleanup()
        {
            if (MessageBox.Show(this,
                "将恢复所有改名程序、启动广告配置和相关服务。\n\n确定继续吗？",
                "恢复原状", MessageBoxButtons.OKCancel, MessageBoxIcon.Question) != DialogResult.OK)
            {
                return;
            }
            if (!ConfirmMuMuClosed()) return;

            RunOperation("正在恢复…", delegate
            {
                HostCleaner.Restore(stateDir, AppendLogFromWorker);
            }, "恢复完成");
        }

        private bool ConfirmMuMuClosed()
        {
            if (!HostCleaner.MuMuIsRunning())
            {
                return true;
            }
            DialogResult result = MessageBox.Show(this,
                "检测到 MuMu 正在运行。为避免文件被占用，需要关闭 MuMu。\n\n现在自动关闭并继续吗？",
                "MuMu 正在运行", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Warning);
            if (result == DialogResult.Cancel || result == DialogResult.No)
            {
                return false;
            }
            HostCleaner.StopMuMuProcesses(AppendLogFromWorker);
            return true;
        }

        private void RunOperation(string pendingText, Action operation, string successText)
        {
            SetBusy(true);
            AppendLog(pendingText);
            ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    operation();
                    BeginInvoke(new Action(delegate
                    {
                        SetBusy(false);
                        RefreshStatus();
                        MessageBox.Show(this, successText, Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
                    }));
                }
                catch (Exception ex)
                {
                    BeginInvoke(new Action(delegate
                    {
                        SetBusy(false);
                        AppendLog("操作失败：" + ex.Message);
                        MessageBox.Show(this, ex.Message, "操作失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    }));
                }
            });
        }

        private void SetBusy(bool busy)
        {
            applyButton.Enabled = !busy;
            restoreButton.Enabled = !busy && HostCleaner.GetStatus(CurrentRoots(), dataDir, stateDir).CleanupStateExists;
            refreshButton.Enabled = !busy;
            browseButton.Enabled = !busy;
            guardCheck.Enabled = !busy;
            serviceCheck.Enabled = !busy;
            UseWaitCursor = busy;
        }

        private void AppendLogFromWorker(string text)
        {
            if (IsDisposed) return;
            BeginInvoke(new Action(delegate { AppendLog(text); }));
        }

        private void AppendLog(string text)
        {
            string line = "[" + DateTime.Now.ToString("HH:mm:ss") + "] " + (text ?? "");
            logBox.AppendText(line + Environment.NewLine);
            logBox.SelectionStart = logBox.TextLength;
            logBox.ScrollToCaret();
        }
    }
}
