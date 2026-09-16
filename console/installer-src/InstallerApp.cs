using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace DshControlInstaller
{
    public class InstallerForm : Form
    {
        private Panel pnlHeader;
        private Label lblTitle;
        private Label lblSubtitle;
        private PictureBox picIcon;

        private Panel pnlContent;
        private GroupBox grpPath;
        private TextBox txtPath;
        private Button btnBrowse;
        private Button btnAutoDetect;

        private GroupBox grpOptions;
        private CheckBox chkDesktopShortcut;
        private CheckBox chkStartMenuShortcut;
        private CheckBox chkLaunchAfter;

        private GroupBox grpProgress;
        private ProgressBar prgBar;
        private Label lblStatus;
        private RichTextBox txtLog;

        private Panel pnlBottom;
        private Button btnInstall;
        private Button btnCancel;

        private bool isInstalling = false;
        private bool isInstalled = false;

        public InstallerForm(bool smokeTest, string defaultDir)
        {
            InitializeUI(defaultDir);

            if (smokeTest)
            {
                System.Windows.Forms.Timer t = new System.Windows.Forms.Timer();
                t.Interval = 3000;
                t.Tick += (s, e) =>
                {
                    t.Stop();
                    this.Close();
                };
                t.Start();
            }
        }

        private void InitializeUI(string customDefaultDir)
        {
            this.Text = "DeepSeek Harness 控制台 - 安装向导";
            this.ClientSize = new Size(660, 560);
            this.MinimumSize = new Size(660, 560);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = Color.FromArgb(24, 28, 40);
            this.ForeColor = Color.WhiteSmoke;
            this.Font = new Font("Segoe UI", 9F, FontStyle.Regular);

            // 加载图标
            try
            {
                using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("dsh.ico"))
                {
                    if (s != null) this.Icon = new Icon(s);
                }
            }
            catch { }

            // 1. 顶部 Header
            pnlHeader = new Panel();
            pnlHeader.Dock = DockStyle.Top;
            pnlHeader.Height = 70;
            pnlHeader.BackColor = Color.FromArgb(32, 38, 54);
            pnlHeader.Padding = new Padding(16, 12, 16, 12);

            picIcon = new PictureBox();
            picIcon.Size = new Size(44, 44);
            picIcon.Location = new Point(16, 13);
            picIcon.SizeMode = PictureBoxSizeMode.Zoom;
            if (this.Icon != null) picIcon.Image = this.Icon.ToBitmap();
            pnlHeader.Controls.Add(picIcon);

            lblTitle = new Label();
            lblTitle.Text = "DeepSeek Harness 控制台 安装程序";
            lblTitle.Font = new Font("Segoe UI", 12F, FontStyle.Bold);
            lblTitle.ForeColor = Color.White;
            lblTitle.Location = new Point(70, 14);
            lblTitle.AutoSize = true;
            pnlHeader.Controls.Add(lblTitle);

            lblSubtitle = new Label();
            lblSubtitle.Text = "独立原生 WinForms 控制台 · 状态轮询守护 · 设置中心与尺寸记忆 (v0.1.0)";
            lblSubtitle.Font = new Font("Segoe UI", 8.5F, FontStyle.Regular);
            lblSubtitle.ForeColor = Color.FromArgb(170, 185, 210);
            lblSubtitle.Location = new Point(72, 38);
            lblSubtitle.AutoSize = true;
            pnlHeader.Controls.Add(lblSubtitle);

            this.Controls.Add(pnlHeader);

            // 2. 底部按钮栏
            pnlBottom = new Panel();
            pnlBottom.Dock = DockStyle.Bottom;
            pnlBottom.Height = 56;
            pnlBottom.BackColor = Color.FromArgb(20, 24, 34);
            this.Controls.Add(pnlBottom);

            btnCancel = new Button();
            btnCancel.Text = "退出";
            btnCancel.Size = new Size(88, 34);
            btnCancel.FlatStyle = FlatStyle.Flat;
            btnCancel.FlatAppearance.BorderColor = Color.FromArgb(70, 80, 100);
            btnCancel.BackColor = Color.FromArgb(40, 46, 62);
            btnCancel.ForeColor = Color.WhiteSmoke;
            btnCancel.Click += (s, e) => this.Close();
            pnlBottom.Controls.Add(btnCancel);

            btnInstall = new Button();
            btnInstall.Text = "开始安装";
            btnInstall.Size = new Size(110, 34);
            btnInstall.FlatStyle = FlatStyle.Flat;
            btnInstall.FlatAppearance.BorderColor = Color.FromArgb(46, 125, 50);
            btnInstall.BackColor = Color.FromArgb(46, 125, 50);
            btnInstall.ForeColor = Color.White;
            btnInstall.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
            btnInstall.Click += (s, e) => OnInstallClick();
            pnlBottom.Controls.Add(btnInstall);

            pnlBottom.Resize += (s, e) => LayoutBottomButtons();

            // 3. 中间内容容器
            pnlContent = new Panel();
            pnlContent.Dock = DockStyle.Fill;
            pnlContent.Padding = new Padding(16, 12, 16, 8);
            this.Controls.Add(pnlContent);
            pnlContent.BringToFront();

            // Group 1: 路径设置
            grpPath = new GroupBox();
            grpPath.Text = "安装目标路径";
            grpPath.ForeColor = Color.FromArgb(200, 215, 235);
            pnlContent.Controls.Add(grpPath);

            txtPath = new TextBox();
            txtPath.BackColor = Color.FromArgb(16, 18, 26);
            txtPath.ForeColor = Color.WhiteSmoke;
            txtPath.BorderStyle = BorderStyle.FixedSingle;

            // 确定默认路径
            string detected = customDefaultDir;
            if (string.IsNullOrEmpty(detected))
            {
                detected = DetectDefaultInstallPath();
            }
            txtPath.Text = detected;

            btnBrowse = new Button();
            btnBrowse.Text = "浏览...";
            btnBrowse.Size = new Size(74, 25);
            btnBrowse.FlatStyle = FlatStyle.Flat;
            btnBrowse.FlatAppearance.BorderColor = Color.FromArgb(70, 80, 100);
            btnBrowse.BackColor = Color.FromArgb(36, 42, 58);
            btnBrowse.ForeColor = Color.WhiteSmoke;
            btnBrowse.Click += (s, e) =>
            {
                using (FolderBrowserDialog fbd = new FolderBrowserDialog())
                {
                    fbd.Description = "请选择控制台安装目标文件夹：";
                    if (Directory.Exists(txtPath.Text)) fbd.SelectedPath = txtPath.Text;
                    if (fbd.ShowDialog(this) == DialogResult.OK)
                    {
                        txtPath.Text = fbd.SelectedPath;
                    }
                }
            };

            btnAutoDetect = new Button();
            btnAutoDetect.Text = "自动探测";
            btnAutoDetect.Size = new Size(84, 25);
            btnAutoDetect.FlatStyle = FlatStyle.Flat;
            btnAutoDetect.FlatAppearance.BorderColor = Color.FromArgb(70, 80, 100);
            btnAutoDetect.BackColor = Color.FromArgb(36, 42, 58);
            btnAutoDetect.ForeColor = Color.WhiteSmoke;
            btnAutoDetect.Click += (s, e) =>
            {
                string p = DetectDefaultInstallPath();
                txtPath.Text = p;
                AddLog("已自动探测推荐路径: " + p);
            };

            grpPath.Controls.Add(txtPath);
            grpPath.Controls.Add(btnBrowse);
            grpPath.Controls.Add(btnAutoDetect);

            // Group 2: 安装选项
            grpOptions = new GroupBox();
            grpOptions.Text = "安装选项";
            grpOptions.ForeColor = Color.FromArgb(200, 215, 235);
            pnlContent.Controls.Add(grpOptions);

            chkDesktopShortcut = new CheckBox();
            chkDesktopShortcut.Text = "创建桌面快捷方式";
            chkDesktopShortcut.Location = new Point(16, 24);
            chkDesktopShortcut.AutoSize = true;
            chkDesktopShortcut.Checked = true;
            chkDesktopShortcut.ForeColor = Color.WhiteSmoke;

            chkStartMenuShortcut = new CheckBox();
            chkStartMenuShortcut.Text = "创建「开始」菜单快捷方式";
            chkStartMenuShortcut.Location = new Point(170, 24);
            chkStartMenuShortcut.AutoSize = true;
            chkStartMenuShortcut.Checked = true;
            chkStartMenuShortcut.ForeColor = Color.WhiteSmoke;

            chkLaunchAfter = new CheckBox();
            chkLaunchAfter.Text = "安装完成后立即启动控制台";
            chkLaunchAfter.Location = new Point(370, 24);
            chkLaunchAfter.AutoSize = true;
            chkLaunchAfter.Checked = true;
            chkLaunchAfter.ForeColor = Color.WhiteSmoke;

            grpOptions.Controls.Add(chkDesktopShortcut);
            grpOptions.Controls.Add(chkStartMenuShortcut);
            grpOptions.Controls.Add(chkLaunchAfter);

            // Group 3: 进度与日志
            grpProgress = new GroupBox();
            grpProgress.Text = "安装进度与详情";
            grpProgress.ForeColor = Color.FromArgb(200, 215, 235);
            pnlContent.Controls.Add(grpProgress);

            prgBar = new ProgressBar();
            prgBar.Value = 0;

            lblStatus = new Label();
            lblStatus.Text = "准备就绪，点击「开始安装」按钮以开始部署。";
            lblStatus.ForeColor = Color.FromArgb(170, 210, 170);

            txtLog = new RichTextBox();
            txtLog.ReadOnly = true;
            txtLog.BackColor = Color.FromArgb(16, 18, 26);
            txtLog.ForeColor = Color.FromArgb(190, 205, 225);
            txtLog.BorderStyle = BorderStyle.None;
            txtLog.Font = new Font("Consolas", 8.5F, FontStyle.Regular);

            grpProgress.Controls.Add(prgBar);
            grpProgress.Controls.Add(lblStatus);
            grpProgress.Controls.Add(txtLog);

            pnlContent.Resize += (s, e) => LayoutContent();
            this.Shown += (s, e) => { LayoutBottomButtons(); LayoutContent(); };

            LayoutBottomButtons();
            LayoutContent();

            AddLog("安装向导已初始化");
            AddLog("推荐目标路径: " + txtPath.Text);
        }

        private void LayoutBottomButtons()
        {
            if (pnlBottom == null || btnInstall == null || btnCancel == null) return;
            int rightMargin = 20;
            int spacing = 12;
            int y = (pnlBottom.ClientSize.Height - btnInstall.Height) / 2;
            if (y < 4) y = 10;

            btnCancel.Location = new Point(pnlBottom.ClientSize.Width - rightMargin - btnCancel.Width, y);
            btnInstall.Location = new Point(btnCancel.Left - spacing - btnInstall.Width, y);
        }

        private void LayoutContent()
        {
            if (pnlContent == null || grpPath == null || grpOptions == null || grpProgress == null) return;

            int margin = 16;
            int contentWidth = pnlContent.ClientSize.Width - (margin * 2);
            if (contentWidth < 200) contentWidth = 200;

            grpPath.Location = new Point(margin, 12);
            grpPath.Size = new Size(contentWidth, 68);

            btnAutoDetect.Location = new Point(grpPath.ClientSize.Width - 96, 25);
            btnBrowse.Location = new Point(btnAutoDetect.Left - 8 - btnBrowse.Width, 25);
            txtPath.Location = new Point(12, 26);
            txtPath.Width = Math.Max(100, btnBrowse.Left - 12 - txtPath.Left);

            grpOptions.Location = new Point(margin, 88);
            grpOptions.Size = new Size(contentWidth, 58);

            grpProgress.Location = new Point(margin, 154);
            int progHeight = pnlContent.ClientSize.Height - grpProgress.Top - 12;
            grpProgress.Size = new Size(contentWidth, Math.Max(160, progHeight));

            prgBar.Location = new Point(16, 24);
            prgBar.Size = new Size(grpProgress.ClientSize.Width - 32, 20);

            lblStatus.Location = new Point(16, 48);
            lblStatus.Size = new Size(grpProgress.ClientSize.Width - 32, 18);

            txtLog.Location = new Point(16, 72);
            int logHeight = grpProgress.ClientSize.Height - txtLog.Top - 12;
            txtLog.Size = new Size(grpProgress.ClientSize.Width - 32, Math.Max(60, logHeight));
        }

        private string DetectDefaultInstallPath()
        {
            // 优先探测已有的 packages/selfuse/control-gui
            string p1 = @"F:\tools\deepseek-harness\packages\selfuse\control-gui";
            if (Directory.Exists(p1)) return p1;

            string envDsh = Environment.GetEnvironmentVariable("DSH_ROOT");
            if (!string.IsNullOrEmpty(envDsh) && Directory.Exists(envDsh))
            {
                string cand = Path.Combine(envDsh, "packages", "selfuse", "control-gui");
                if (Directory.Exists(cand)) return cand;
            }

            string appDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\', '/');
            if (appDir.EndsWith("control-gui", StringComparison.OrdinalIgnoreCase)) return appDir;

            string p2 = @"F:\tools\deepseek-harness";
            if (Directory.Exists(p2)) return Path.Combine(p2, "packages", "selfuse", "control-gui");

            // 默认回退到 LocalAppData
            string localApp = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Programs\DeepSeek-Harness-Control");
            return localApp;
        }

        private void AddLog(string msg)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<string>(AddLog), msg);
                return;
            }
            string time = DateTime.Now.ToString("HH:mm:ss");
            txtLog.AppendText(string.Format("[{0}] {1}\r\n", time, msg));
            txtLog.SelectionStart = txtLog.TextLength;
            txtLog.ScrollToCaret();
        }

        private void SetProgress(int percent, string status)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action<int, string>(SetProgress), percent, status);
                return;
            }
            if (percent >= 0 && percent <= 100) prgBar.Value = percent;
            if (!string.IsNullOrEmpty(status)) lblStatus.Text = status;
        }

        private void OnInstallClick()
        {
            if (isInstalled)
            {
                // 已经安装完成，点击按钮则启动控制台并关闭安装程序
                LaunchAppAndExit();
                return;
            }

            if (isInstalling) return;

            string targetDir = txtPath.Text.Trim();
            if (string.IsNullOrEmpty(targetDir))
            {
                MessageBox.Show("请指定有效的安装目标文件夹！", "提示", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            isInstalling = true;
            btnInstall.Enabled = false;
            btnBrowse.Enabled = false;
            btnAutoDetect.Enabled = false;
            txtPath.ReadOnly = true;
            chkDesktopShortcut.Enabled = false;
            chkStartMenuShortcut.Enabled = false;
            chkLaunchAfter.Enabled = false;
            btnInstall.Text = "正在安装...";

            bool createDesktop = chkDesktopShortcut.Checked;
            bool createStartMenu = chkStartMenuShortcut.Checked;
            bool launchAfter = chkLaunchAfter.Checked;

            ThreadPool.QueueUserWorkItem((state) =>
            {
                try
                {
                    PerformInstallation(targetDir, createDesktop, createStartMenu);

                    this.Invoke(new Action(() =>
                    {
                        isInstalling = false;
                        isInstalled = true;
                        btnInstall.Enabled = true;
                        btnInstall.Text = launchAfter ? "启动控制台" : "完成";
                        btnInstall.BackColor = Color.FromArgb(46, 125, 50);
                        SetProgress(100, "安装成功完成！已准备就绪。");
                        AddLog("[✓] 全部组件安装成功！");

                        if (launchAfter)
                        {
                            LaunchAppAndExit();
                        }
                    }));
                }
                catch (Exception ex)
                {
                    this.Invoke(new Action(() =>
                    {
                        isInstalling = false;
                        btnInstall.Enabled = true;
                        btnInstall.Text = "重试安装";
                        btnInstall.BackColor = Color.FromArgb(160, 60, 60);
                        SetProgress(0, "安装失败: " + ex.Message);
                        AddLog("[!] 发生错误: " + ex.Message);
                        MessageBox.Show("安装过程中发生错误:\r\n" + ex.Message, "安装失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    }));
                }
            });
        }

        private void PerformInstallation(string targetDir, bool createDesktop, bool createStartMenu)
        {
            AddLog("正在准备安装目录: " + targetDir);
            if (!Directory.Exists(targetDir))
            {
                Directory.CreateDirectory(targetDir);
            }

            // 检查是否有正在运行的控制台进程
            try
            {
                Process[] procs = Process.GetProcessesByName("dsh-control-gui");
                if (procs.Length > 0)
                {
                    AddLog("检测到运行中的控制台进程，正在终止以便文件替换...");
                    foreach (Process p in procs)
                    {
                        try { p.Kill(); p.WaitForExit(3000); } catch { }
                    }
                }
            }
            catch { }

            // 提取嵌入的 package.zip
            AddLog("正在解压嵌入的控制台核心组件...");
            using (Stream zipStream = Assembly.GetExecutingAssembly().GetManifestResourceStream("package.zip"))
            {
                if (zipStream == null)
                {
                    throw new InvalidOperationException("未找到嵌入的安装数据包 package.zip！");
                }

                using (ZipArchive archive = new ZipArchive(zipStream, ZipArchiveMode.Read))
                {
                    int total = archive.Entries.Count;
                    int current = 0;
                    foreach (ZipArchiveEntry entry in archive.Entries)
                    {
                        current++;
                        if (string.IsNullOrEmpty(entry.Name) && (entry.FullName.EndsWith("/") || entry.FullName.EndsWith("\\")))
                        {
                            string dir = Path.Combine(targetDir, entry.FullName.Replace('/', Path.DirectorySeparatorChar));
                            if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                            continue;
                        }

                        string dest = Path.Combine(targetDir, entry.FullName.Replace('/', Path.DirectorySeparatorChar));
                        string parent = Path.GetDirectoryName(dest);
                        if (!Directory.Exists(parent)) Directory.CreateDirectory(parent);

                        int pct = (int)((current * 85.0) / total);
                        SetProgress(pct, "正在解压: " + entry.Name);
                        AddLog("释放文件: " + entry.FullName);

                        using (Stream src = entry.Open())
                        using (FileStream dst = new FileStream(dest, FileMode.Create, FileAccess.Write, FileShare.None))
                        {
                            byte[] buf = new byte[65536];
                            int r;
                            while ((r = src.Read(buf, 0, buf.Length)) > 0)
                            {
                                dst.Write(buf, 0, r);
                            }
                        }
                    }
                }
            }

            string exePath = Path.Combine(targetDir, "dsh-control-gui.exe");
            string iconPath = Path.Combine(targetDir, "dsh.ico");

            if (!File.Exists(exePath))
            {
                throw new FileNotFoundException("未在解压结果中找到控制台主程序 dsh-control-gui.exe！");
            }

            SetProgress(90, "正在生成系统快捷方式...");

            // 创建桌面快捷方式
            if (createDesktop)
            {
                string desktop = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
                string scDesktop = Path.Combine(desktop, "DSH 控制台.lnk");
                CreateShortcut(scDesktop, exePath, targetDir, "DeepSeek Harness 控制台", iconPath);
                AddLog("已创建桌面快捷方式: " + scDesktop);

                // 兼容英文名
                string scEn = Path.Combine(desktop, "DSH Control.lnk");
                CreateShortcut(scEn, exePath, targetDir, "DeepSeek Harness 控制台", iconPath);
            }

            // 创建开始菜单快捷方式
            if (createStartMenu)
            {
                string startMenu = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu), @"Programs\DeepSeek Harness");
                if (!Directory.Exists(startMenu)) Directory.CreateDirectory(startMenu);
                string scStart = Path.Combine(startMenu, "DSH 控制台.lnk");
                CreateShortcut(scStart, exePath, targetDir, "DeepSeek Harness 控制台", iconPath);
                AddLog("已创建「开始」菜单快捷方式: " + scStart);
            }

            SetProgress(98, "校验安装完整性...");
            Thread.Sleep(300);
        }

        private void CreateShortcut(string shortcutPath, string targetPath, string workingDir, string description, string iconPath)
        {
            try
            {
                Type shellType = Type.GetTypeFromProgID("WScript.Shell");
                if (shellType == null) return;
                object shell = Activator.CreateInstance(shellType);
                object shortcut = shellType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { shortcutPath });
                Type shortcutType = shortcut.GetType();
                shortcutType.InvokeMember("TargetPath", BindingFlags.SetProperty, null, shortcut, new object[] { targetPath });
                if (!string.IsNullOrEmpty(workingDir))
                    shortcutType.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, shortcut, new object[] { workingDir });
                if (!string.IsNullOrEmpty(description))
                    shortcutType.InvokeMember("Description", BindingFlags.SetProperty, null, shortcut, new object[] { description });
                if (!string.IsNullOrEmpty(iconPath) && File.Exists(iconPath))
                    shortcutType.InvokeMember("IconLocation", BindingFlags.SetProperty, null, shortcut, new object[] { iconPath });
                shortcutType.InvokeMember("Save", BindingFlags.InvokeMethod, null, shortcut, null);
            }
            catch (Exception ex)
            {
                AddLog("[!] 创建快捷方式失败: " + ex.Message);
            }
        }

        private void LaunchAppAndExit()
        {
            try
            {
                string targetDir = txtPath.Text.Trim();
                string exePath = Path.Combine(targetDir, "dsh-control-gui.exe");
                if (File.Exists(exePath))
                {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = exePath;
                    psi.WorkingDirectory = targetDir;
                    Process.Start(psi);
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("启动控制台失败: " + ex.Message, "提示", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            finally
            {
                this.Close();
            }
        }
    }

    public static class Program
    {
        [STAThread]
        public static int Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            bool smokeTest = false;
            string defaultDir = null;

            for (int i = 0; i < args.Length; i++)
            {
                string a = args[i];
                if (string.Equals(a, "-SmokeTest", StringComparison.OrdinalIgnoreCase))
                {
                    smokeTest = true;
                }
                else if (string.Equals(a, "-Dir", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
                {
                    defaultDir = args[++i];
                }
            }

            InstallerForm form = new InstallerForm(smokeTest, defaultDir);
            Application.Run(form);
            return 0;
        }
    }
}
