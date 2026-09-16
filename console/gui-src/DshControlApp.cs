using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace DshControl
{
    public class GuiSettings
    {
        public const string ActiveWslDshHome = @"\\wsl.localhost\Ubuntu\home\huangzy\.dsh";
        public string HarnessRoot { get; set; }
        public string DshHome { get; set; }
        public string BannerImagePath { get; set; }
        public int BannerHeight { get; set; }
        public string BannerSizeMode { get; set; }
        public int WindowWidth { get; set; }
        public int WindowHeight { get; set; }

        public GuiSettings()
        {
            HarnessRoot = @"F:\tools\deepseek-harness";
            DshHome = ActiveWslDshHome;
            BannerImagePath = @"C:\Users\HuangZY\Pictures\IMG_1891.PNG";
            BannerHeight = 280;
            BannerSizeMode = "Zoom";
            WindowWidth = 900;
            WindowHeight = 860;
        }

        public static string SettingsFilePath
        {
            get
            {
                string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".dsh");
                if (!Directory.Exists(dir))
                {
                    try { Directory.CreateDirectory(dir); } catch { }
                }
                return Path.Combine(dir, "gui-settings.json");
            }
        }

        public static string NormalizeDshHome(string value)
        {
            string legacyHome = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".dsh");
            if (string.IsNullOrWhiteSpace(value) || string.Equals(value.TrimEnd('\\', '/'), legacyHome, StringComparison.OrdinalIgnoreCase))
            {
                return ActiveWslDshHome;
            }
            return value;
        }

        public static GuiSettings Load()
        {
            GuiSettings s = new GuiSettings();
            try
            {
                string path = SettingsFilePath;
                if (File.Exists(path))
                {
                    string json = File.ReadAllText(path, Encoding.UTF8);
                    JavaScriptSerializer js = new JavaScriptSerializer();
                    GuiSettings loaded = js.Deserialize<GuiSettings>(json);
                    if (loaded != null)
                    {
                        if (!string.IsNullOrEmpty(loaded.HarnessRoot)) s.HarnessRoot = loaded.HarnessRoot;
                        s.DshHome = NormalizeDshHome(loaded.DshHome);
                        if (!string.IsNullOrEmpty(loaded.BannerImagePath)) s.BannerImagePath = loaded.BannerImagePath;
                        if (loaded.BannerHeight >= 0 && loaded.BannerHeight <= 800) s.BannerHeight = loaded.BannerHeight;
                        if (!string.IsNullOrEmpty(loaded.BannerSizeMode)) s.BannerSizeMode = loaded.BannerSizeMode;
                        if (loaded.WindowWidth >= 700) s.WindowWidth = loaded.WindowWidth;
                        if (loaded.WindowHeight >= 600) s.WindowHeight = loaded.WindowHeight;
                        return s;
                    }
                }
            }
            catch { }

            // 智能初次检测并持久化保存初始配置
            s.AutoDetectDefaults();
            s.Save();
            return s;
        }

        public void Save()
        {
            try
            {
                string path = SettingsFilePath;
                JavaScriptSerializer js = new JavaScriptSerializer();
                string json = js.Serialize(this);
                File.WriteAllText(path, json, Encoding.UTF8);
            }
            catch (Exception ex)
            {
                MessageBox.Show("保存配置失败: " + ex.Message, "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        public void AutoDetectDefaults()
        {
            string appDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\', '/');
            if (IsValidHarnessRoot(appDir))
            {
                HarnessRoot = appDir;
                return;
            }

            string parent = Path.GetDirectoryName(appDir);
            if (!string.IsNullOrEmpty(parent) && IsValidHarnessRoot(parent))
            {
                HarnessRoot = parent;
                return;
            }

            string dshRootEnv = Environment.GetEnvironmentVariable("DSH_ROOT");
            if (!string.IsNullOrEmpty(dshRootEnv) && IsValidHarnessRoot(dshRootEnv))
            {
                HarnessRoot = dshRootEnv;
                return;
            }

            List<string> found = AutoSearchHarnessRoots();
            if (found.Count > 0)
            {
                HarnessRoot = found[0];
            }
        }

        public static bool IsValidHarnessRoot(string dir)
        {
            if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return false;
            try
            {
                string pkg = Path.Combine(dir, "package.json");
                if (File.Exists(pkg))
                {
                    string text = File.ReadAllText(pkg, Encoding.UTF8);
                    if (text.Contains("\"name\": \"@deepseek-ai/dsh-root\"") || text.Contains("\"@deepseek-ai/dsh-root\""))
                    {
                        return true;
                    }
                }
                bool hasRunWeb = File.Exists(Path.Combine(dir, "run-dsh-web.ps1"));
                bool hasDshControl = File.Exists(Path.Combine(dir, "dsh-control.ps1"));
                bool hasHarnessStructure = Directory.Exists(Path.Combine(dir, "packages")) || Directory.Exists(Path.Combine(dir, "apps")) || File.Exists(Path.Combine(dir, "pnpm-workspace.yaml"));
                if ((hasRunWeb || hasDshControl) && hasHarnessStructure)
                {
                    return true;
                }
            }
            catch { }
            return false;
        }

        public static List<string> AutoSearchHarnessRoots()
        {
            List<string> results = new List<string>();
            HashSet<string> scanned = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            Action<string> checkAndAdd = (candidate) =>
            {
                if (string.IsNullOrEmpty(candidate)) return;
                try
                {
                    string full = Path.GetFullPath(candidate).TrimEnd('\\', '/');
                    if (scanned.Contains(full)) return;
                    scanned.Add(full);
                    if (IsValidHarnessRoot(full))
                    {
                        results.Add(full);
                    }
                }
                catch { }
            };

            // 1. 当前程序目录及各级上级目录
            try
            {
                string cur = AppDomain.CurrentDomain.BaseDirectory;
                while (!string.IsNullOrEmpty(cur))
                {
                    checkAndAdd(cur);
                    DirectoryInfo di = Directory.GetParent(cur);
                    cur = di != null ? di.FullName : null;
                }
            }
            catch { }

            // 2. 环境变量 DSH_ROOT
            string envRoot = Environment.GetEnvironmentVariable("DSH_ROOT");
            checkAndAdd(envRoot);

            // 3. 常见候选路径
            string[] commonPaths = new string[]
            {
                @"F:\tools\deepseek-harness",
                @"F:\tools",
                @"D:\tools\deepseek-harness",
                @"D:\tools",
                @"C:\tools\deepseek-harness",
                @"C:\tools",
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "tools", "deepseek-harness"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "deepseek-harness"),
                @"\\wsl.localhost\Ubuntu\home\huangzy\tools\deepseek-harness",
                @"\\wsl$\Ubuntu\home\huangzy\tools\deepseek-harness"
            };
            foreach (string cp in commonPaths)
            {
                checkAndAdd(cp);
            }

            // 4. 在 F:\, D:\, C:\ 的常用开发根目录下浅层搜索 (深度 2)
            string[] probeDrives = new string[] { @"F:\", @"D:\", @"C:\" };
            foreach (string drive in probeDrives)
            {
                if (!Directory.Exists(drive)) continue;
                try
                {
                    string[] subdirs = Directory.GetDirectories(drive);
                    foreach (string sub in subdirs)
                    {
                        string leaf = Path.GetFileName(sub).ToLowerInvariant();
                        if (leaf == "tools" || leaf == "workspace" || leaf == "projects" || leaf == "repo" || leaf.Contains("deepseek") || leaf.Contains("dsh"))
                        {
                            checkAndAdd(sub);
                            try
                            {
                                string[] deep = Directory.GetDirectories(sub);
                                foreach (string d in deep)
                                {
                                    checkAndAdd(d);
                                }
                            }
                            catch { }
                        }
                    }
                }
                catch { }
            }

            return results;
        }
    }

    public class SettingsForm : Form
    {
        private GuiSettings settings;
        private TextBox txtHarnessRoot;
        private TextBox txtDshHome;
        private TextBox txtBannerPath;
        private TrackBar tbBannerHeight;
        private NumericUpDown numBannerHeight;
        private ComboBox cbSizeMode;
        private PictureBox picPreview;
        private Label lblSearchStatus;
        private Label lblCandidates;
        private ComboBox cbCandidateRoots;
        public bool SettingsChanged { get; private set; }

        public SettingsForm(GuiSettings currentSettings)
        {
            this.settings = currentSettings;
            this.SettingsChanged = false;
            InitializeUI();
            LoadFromSettings();
        }

        private void InitializeUI()
        {
            this.Text = "控制台设置";
            this.ClientSize = new Size(680, 670);
            this.MinimumSize = new Size(640, 620);
            this.StartPosition = FormStartPosition.CenterParent;
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.BackColor = Color.FromArgb(26, 30, 42);
            this.ForeColor = Color.WhiteSmoke;
            this.Font = new Font("Microsoft YaHei UI", 9.5f);

            Panel pnlContent = new Panel();
            pnlContent.Dock = DockStyle.Fill;
            pnlContent.AutoScroll = true;
            pnlContent.Padding = new Padding(16, 12, 16, 12);
            this.Controls.Add(pnlContent);

            // 1. 横幅与外观
            GroupBox grpBanner = new GroupBox();
            grpBanner.Text = "横幅与外观设置";
            grpBanner.ForeColor = Color.FromArgb(100, 180, 255);
            grpBanner.BackColor = Color.FromArgb(32, 38, 52);
            grpBanner.Location = new Point(16, 12);
            grpBanner.Size = new Size(630, 275);

            Label lblPath = new Label() { Text = "背景图片路径:", Location = new Point(16, 26), AutoSize = true, ForeColor = Color.WhiteSmoke };
            txtBannerPath = new TextBox() { Location = new Point(16, 48), Size = new Size(420, 26), BackColor = Color.FromArgb(20, 24, 36), ForeColor = Color.WhiteSmoke, BorderStyle = BorderStyle.FixedSingle };
            Button btnBrowseBanner = CreateButton("浏览...", new Point(444, 46), new Size(76, 28), Color.FromArgb(50, 60, 80));
            btnBrowseBanner.Click += (s, e) =>
            {
                using (OpenFileDialog ofd = new OpenFileDialog())
                {
                    ofd.Title = "选择背景图片";
                    ofd.Filter = "图片文件 (*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp)|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp|所有文件 (*.*)|*.*";
                    if (File.Exists(txtBannerPath.Text))
                    {
                        ofd.InitialDirectory = Path.GetDirectoryName(txtBannerPath.Text);
                        ofd.FileName = Path.GetFileName(txtBannerPath.Text);
                    }
                    if (ofd.ShowDialog(this) == DialogResult.OK)
                    {
                        txtBannerPath.Text = ofd.FileName;
                        UpdatePreview();
                    }
                }
            };
            Button btnClearBanner = CreateButton("清除", new Point(526, 46), new Size(60, 28), Color.FromArgb(80, 50, 50));
            btnClearBanner.Click += (s, e) => { txtBannerPath.Text = ""; UpdatePreview(); };

            Label lblHeight = new Label() { Text = "横幅高度 (0~500 px，0 为隐藏折叠):", Location = new Point(16, 84), AutoSize = true, ForeColor = Color.WhiteSmoke };
            tbBannerHeight = new TrackBar() { Location = new Point(16, 106), Size = new Size(310, 36), Minimum = 0, Maximum = 500, TickFrequency = 50 };
            numBannerHeight = new NumericUpDown() { Location = new Point(334, 108), Size = new Size(80, 26), Minimum = 0, Maximum = 500, BackColor = Color.FromArgb(20, 24, 36), ForeColor = Color.WhiteSmoke, BorderStyle = BorderStyle.FixedSingle };
            tbBannerHeight.ValueChanged += (s, e) => { numBannerHeight.Value = tbBannerHeight.Value; };
            numBannerHeight.ValueChanged += (s, e) => { tbBannerHeight.Value = (int)numBannerHeight.Value; };

            // 快捷高度预设按钮
            Button btnH0 = CreateButton("隐藏(0)", new Point(16, 146), new Size(70, 26), Color.FromArgb(45, 52, 68));
            btnH0.Click += (s, e) => { tbBannerHeight.Value = 0; };
            Button btnH180 = CreateButton("紧凑(180)", new Point(92, 146), new Size(76, 26), Color.FromArgb(45, 52, 68));
            btnH180.Click += (s, e) => { tbBannerHeight.Value = 180; };
            Button btnH280 = CreateButton("标准(280)", new Point(174, 146), new Size(76, 26), Color.FromArgb(45, 52, 68));
            btnH280.Click += (s, e) => { tbBannerHeight.Value = 280; };
            Button btnH380 = CreateButton("大图(380)", new Point(256, 146), new Size(76, 26), Color.FromArgb(45, 52, 68));
            btnH380.Click += (s, e) => { tbBannerHeight.Value = 380; };

            Label lblMode = new Label() { Text = "显示缩放模式:", Location = new Point(16, 184), AutoSize = true, ForeColor = Color.WhiteSmoke };
            cbSizeMode = new ComboBox() { Location = new Point(16, 206), Size = new Size(200, 26), DropDownStyle = ComboBoxStyle.DropDownList, BackColor = Color.FromArgb(20, 24, 36), ForeColor = Color.WhiteSmoke };
            cbSizeMode.Items.AddRange(new object[] { "Zoom (等比缩放)", "Stretch (拉伸铺满)", "Center (居中显示)" });
            cbSizeMode.SelectedIndex = 0;
            cbSizeMode.SelectedIndexChanged += (s, e) =>
            {
                if (cbSizeMode.SelectedIndex == 1) picPreview.SizeMode = PictureBoxSizeMode.StretchImage;
                else if (cbSizeMode.SelectedIndex == 2) picPreview.SizeMode = PictureBoxSizeMode.CenterImage;
                else picPreview.SizeMode = PictureBoxSizeMode.Zoom;
            };

            picPreview = new PictureBox()
            {
                Location = new Point(430, 84),
                Size = new Size(180, 148),
                BorderStyle = BorderStyle.FixedSingle,
                SizeMode = PictureBoxSizeMode.Zoom,
                BackColor = Color.FromArgb(20, 24, 36)
            };

            grpBanner.Controls.AddRange(new Control[] {
                lblPath, txtBannerPath, btnBrowseBanner, btnClearBanner,
                lblHeight, tbBannerHeight, numBannerHeight,
                btnH0, btnH180, btnH280, btnH380,
                lblMode, cbSizeMode, picPreview
            });
            pnlContent.Controls.Add(grpBanner);

            // 2. 工作区与功能目录
            GroupBox grpHarness = new GroupBox();
            grpHarness.Text = "工作区与功能目录 (Harness Root)";
            grpHarness.ForeColor = Color.FromArgb(100, 180, 255);
            grpHarness.BackColor = Color.FromArgb(32, 38, 52);
            grpHarness.Location = new Point(16, 295);
            grpHarness.Size = new Size(630, 255);

            Label lblRoot = new Label() { Text = "DSH 源码/功能目录 (deepseek-harness 所在目录):", Location = new Point(16, 24), AutoSize = true, ForeColor = Color.WhiteSmoke };
            txtHarnessRoot = new TextBox() { Location = new Point(16, 46), Size = new Size(504, 26), BackColor = Color.FromArgb(20, 24, 36), ForeColor = Color.WhiteSmoke, BorderStyle = BorderStyle.FixedSingle };
            Button btnBrowseRoot = CreateButton("浏览...", new Point(526, 44), new Size(76, 28), Color.FromArgb(50, 60, 80));
            btnBrowseRoot.Click += (s, e) =>
            {
                using (FolderBrowserDialog fbd = new FolderBrowserDialog())
                {
                    fbd.Description = "选择 deepseek-harness 根目录";
                    if (Directory.Exists(txtHarnessRoot.Text)) fbd.SelectedPath = txtHarnessRoot.Text;
                    if (fbd.ShowDialog(this) == DialogResult.OK)
                    {
                        txtHarnessRoot.Text = fbd.SelectedPath;
                    }
                }
            };

            Button btnAutoSearch = CreateButton("🔍 一键自动搜索功能目录", new Point(16, 80), new Size(190, 30), Color.FromArgb(40, 90, 60));
            btnAutoSearch.Font = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Bold);
            lblSearchStatus = new Label() { Location = new Point(212, 84), Size = new Size(400, 24), ForeColor = Color.LightGreen, Text = "" };

            lblCandidates = new Label() { Text = "候选目录 (点击下拉选择):", Location = new Point(16, 116), AutoSize = true, ForeColor = Color.LightSkyBlue, Visible = false };
            cbCandidateRoots = new ComboBox() { Location = new Point(16, 138), Size = new Size(504, 26), DropDownStyle = ComboBoxStyle.DropDownList, Visible = false, BackColor = Color.FromArgb(20, 24, 36), ForeColor = Color.WhiteSmoke };
            cbCandidateRoots.SelectedIndexChanged += (s, e) =>
            {
                if (cbCandidateRoots.SelectedItem != null)
                {
                    txtHarnessRoot.Text = cbCandidateRoots.SelectedItem.ToString();
                }
            };

            btnAutoSearch.Click += (s, e) =>
            {
                btnAutoSearch.Enabled = false;
                lblSearchStatus.ForeColor = Color.Yellow;
                lblSearchStatus.Text = "正在扫描系统盘符与目录...";
                ThreadPool.QueueUserWorkItem((state) =>
                {
                    List<string> found = GuiSettings.AutoSearchHarnessRoots();
                    this.BeginInvoke(new Action(() =>
                    {
                        btnAutoSearch.Enabled = true;
                        if (found.Count == 0)
                        {
                            lblSearchStatus.ForeColor = Color.OrangeRed;
                            lblSearchStatus.Text = "未自动找到有效的 DSH 目录，请点击浏览手动指定。";
                            lblCandidates.Visible = false;
                            cbCandidateRoots.Visible = false;
                        }
                        else if (found.Count == 1)
                        {
                            txtHarnessRoot.Text = found[0];
                            lblSearchStatus.ForeColor = Color.LightGreen;
                            lblSearchStatus.Text = "✓ 已自动定位: " + found[0];
                            lblCandidates.Visible = false;
                            cbCandidateRoots.Visible = false;
                        }
                        else
                        {
                            txtHarnessRoot.Text = found[0];
                            lblSearchStatus.ForeColor = Color.LightGreen;
                            lblSearchStatus.Text = string.Format("✓ 找到 {0} 个目录，已填入首选，可在下方下拉切换:", found.Count);
                            cbCandidateRoots.Items.Clear();
                            foreach (string dir in found)
                            {
                                cbCandidateRoots.Items.Add(dir);
                            }
                            cbCandidateRoots.SelectedIndex = 0;
                            lblCandidates.Visible = true;
                            cbCandidateRoots.Visible = true;
                        }
                    }));
                });
            };

            Label lblDshHome = new Label() { Text = "DSH 配置目录 (~/.dsh):", Location = new Point(16, 172), AutoSize = true, ForeColor = Color.WhiteSmoke };
            txtDshHome = new TextBox() { Location = new Point(16, 194), Size = new Size(504, 26), BackColor = Color.FromArgb(20, 24, 36), ForeColor = Color.WhiteSmoke, BorderStyle = BorderStyle.FixedSingle };
            Button btnBrowseHome = CreateButton("浏览...", new Point(526, 192), new Size(76, 28), Color.FromArgb(50, 60, 80));
            btnBrowseHome.Click += (s, e) =>
            {
                using (FolderBrowserDialog fbd = new FolderBrowserDialog())
                {
                    fbd.Description = "选择 .dsh 配置目录";
                    if (Directory.Exists(txtDshHome.Text)) fbd.SelectedPath = txtDshHome.Text;
                    if (fbd.ShowDialog(this) == DialogResult.OK)
                    {
                        txtDshHome.Text = fbd.SelectedPath;
                    }
                }
            };

            grpHarness.Controls.AddRange(new Control[] {
                lblRoot, txtHarnessRoot, btnBrowseRoot,
                btnAutoSearch, lblSearchStatus,
                lblCandidates, cbCandidateRoots,
                lblDshHome, txtDshHome, btnBrowseHome
            });
            pnlContent.Controls.Add(grpHarness);

            // 3. 底部操作按钮
            Panel pnlBottom = new Panel();
            pnlBottom.Dock = DockStyle.Bottom;
            pnlBottom.Height = 56;
            pnlBottom.BackColor = Color.FromArgb(20, 24, 36);
            this.Controls.Add(pnlBottom);

            Button btnSave = CreateButton("保存并应用", new Point(360, 12), new Size(110, 32), Color.FromArgb(40, 110, 70));
            btnSave.Font = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Bold);
            btnSave.Click += (s, e) =>
            {
                SaveToSettings();
                this.SettingsChanged = true;
                this.DialogResult = DialogResult.OK;
                this.Close();
            };

            Button btnReset = CreateButton("恢复默认", new Point(20, 12), new Size(96, 32), Color.FromArgb(70, 70, 80));
            btnReset.Click += (s, e) =>
            {
                if (MessageBox.Show("确定将所有设置恢复为默认值吗?", "提示", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
                {
                    GuiSettings def = new GuiSettings();
                    def.AutoDetectDefaults();
                    this.settings = def;
                    LoadFromSettings();
                }
            };

            Button btnCancel = CreateButton("取消", new Point(480, 12), new Size(96, 32), Color.FromArgb(60, 66, 82));
            btnCancel.Click += (s, e) => { this.DialogResult = DialogResult.Cancel; this.Close(); };

            pnlBottom.Controls.AddRange(new Control[] { btnReset, btnSave, btnCancel });
        }

        private Button CreateButton(string text, Point loc, Size size, Color back)
        {
            Button b = new Button();
            b.Text = text;
            b.Location = loc;
            b.Size = size;
            b.FlatStyle = FlatStyle.Flat;
            b.FlatAppearance.BorderColor = Color.FromArgb(70, 80, 100);
            b.BackColor = back;
            b.ForeColor = Color.WhiteSmoke;
            return b;
        }

        private void LoadFromSettings()
        {
            txtBannerPath.Text = settings.BannerImagePath ?? "";
            tbBannerHeight.Value = Math.Max(0, Math.Min(500, settings.BannerHeight));
            numBannerHeight.Value = tbBannerHeight.Value;

            if (settings.BannerSizeMode == "Stretch") cbSizeMode.SelectedIndex = 1;
            else if (settings.BannerSizeMode == "Center") cbSizeMode.SelectedIndex = 2;
            else cbSizeMode.SelectedIndex = 0;

            txtHarnessRoot.Text = settings.HarnessRoot ?? "";
            txtDshHome.Text = settings.DshHome ?? "";

            UpdatePreview();
        }

        private void UpdatePreview()
        {
            try
            {
                if (cbSizeMode.SelectedIndex == 1) picPreview.SizeMode = PictureBoxSizeMode.StretchImage;
                else if (cbSizeMode.SelectedIndex == 2) picPreview.SizeMode = PictureBoxSizeMode.CenterImage;
                else picPreview.SizeMode = PictureBoxSizeMode.Zoom;

                string path = txtBannerPath.Text.Trim();
                if (File.Exists(path))
                {
                    byte[] bytes = File.ReadAllBytes(path);
                    using (MemoryStream ms = new MemoryStream(bytes))
                    {
                        Image img = Image.FromStream(ms);
                        picPreview.Image = new Bitmap(img);
                    }
                }
                else
                {
                    picPreview.Image = null;
                }
            }
            catch
            {
                picPreview.Image = null;
            }
        }

        private void SaveToSettings()
        {
            settings.BannerImagePath = txtBannerPath.Text.Trim();
            settings.BannerHeight = (int)numBannerHeight.Value;
            if (cbSizeMode.SelectedIndex == 1) settings.BannerSizeMode = "Stretch";
            else if (cbSizeMode.SelectedIndex == 2) settings.BannerSizeMode = "Center";
            else settings.BannerSizeMode = "Zoom";

            settings.HarnessRoot = txtHarnessRoot.Text.Trim();
            settings.DshHome = txtDshHome.Text.Trim();
            settings.Save();
        }
    }

    public class MainForm : Form
    {
        private GuiSettings settings;
        private PictureBox bannerBox;
        private GroupBox statusGroup;
        private TableLayoutPanel tblStatus;
        private Dictionary<string, Label> statusLabels = new Dictionary<string, Label>(StringComparer.OrdinalIgnoreCase);
        private FlowLayoutPanel btnPanel;
        private GroupBox logGroup;
        private RichTextBox logBox;
        private StatusStrip statusStrip;
        private ToolStripStatusLabel refreshLabel;
        private System.Windows.Forms.Timer pollTimer;
        private Process pollerProcess = null;
        private string lastStatusRaw = "";
        private bool logTailReady = false;
        private const int StatusMaxAgeSeconds = 15;

        private string TempDir { get { return Path.GetTempPath(); } }
        private string StatusFile { get { return Path.Combine(TempDir, "dsh-gui-status.json"); } }
        private string TriggerFile { get { return Path.Combine(TempDir, "dsh-gui-refresh.trigger"); } }
        private string CmdFile { get { return Path.Combine(TempDir, "dsh-gui-cmd.json"); } }
        private string PollerPidFile { get { return Path.Combine(TempDir, "dsh-gui-poller.pid"); } }
        private string ActivityFile { get { return Path.Combine(TempDir, "dsh-gui-activity.log"); } }
        private string PollerFile { get { return Path.Combine(TempDir, "dsh-gui-poller.ps1"); } }
        private string ResultPrefix { get { return Path.Combine(TempDir, "dsh-gui-result-"); } }

        public MainForm(GuiSettings s, bool smokeTest)
        {
            this.settings = s;
            InitializeUI();

            if (smokeTest)
            {
                System.Windows.Forms.Timer smokeTimer = new System.Windows.Forms.Timer();
                smokeTimer.Interval = 3000;
                smokeTimer.Tick += (sender, args) =>
                {
                    smokeTimer.Stop();
                    this.Close();
                };
                smokeTimer.Start();
            }
        }

        private void InitializeUI()
        {
            this.Text = "dsh 控制台";
            this.ClientSize = new Size(settings.WindowWidth, settings.WindowHeight);
            this.MinimumSize = new Size(760, 720);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.KeyPreview = true;
            this.BackColor = Color.FromArgb(26, 30, 42);

            string iconPath = Path.Combine(settings.HarnessRoot, "dsh.ico");
            if (File.Exists(iconPath))
            {
                try { this.Icon = new Icon(iconPath); } catch { }
            }

            // 1. 顶部横幅
            bannerBox = new PictureBox();
            bannerBox.Dock = DockStyle.Top;
            bannerBox.Height = settings.BannerHeight;
            bannerBox.Visible = settings.BannerHeight > 0;
            bannerBox.BackColor = Color.FromArgb(20, 24, 36);
            ApplyBannerSizeMode();
            ApplyBannerImage();

            // 横幅右键菜单
            ContextMenuStrip bannerMenu = new ContextMenuStrip();
            bannerMenu.Items.Add("控制台设置 (⚙)...", null, (s, e) => OpenSettingsDialog());
            bannerBox.ContextMenuStrip = bannerMenu;

            // 2. 状态面板
            statusGroup = new GroupBox();
            statusGroup.Text = "状态";
            statusGroup.Dock = DockStyle.Top;
            statusGroup.Height = 190;
            statusGroup.Padding = new Padding(8);
            statusGroup.ForeColor = Color.WhiteSmoke;
            statusGroup.BackColor = Color.FromArgb(32, 38, 52);

            tblStatus = new TableLayoutPanel();
            tblStatus.Dock = DockStyle.Fill;
            tblStatus.ColumnCount = 2;
            tblStatus.RowCount = 5;
            tblStatus.BackColor = Color.FromArgb(32, 38, 52);
            tblStatus.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 95f));
            tblStatus.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
            for (int i = 0; i < 5; i++)
            {
                tblStatus.RowStyles.Add(new RowStyle(SizeType.Percent, 20f));
            }
            statusGroup.Controls.Add(tblStatus);

            Font nameFont = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Bold);
            Font valFont = new Font("Microsoft YaHei UI", 9.5f);
            string[] names = new string[] { "web", "watchdog", "WSL", "dsh home", "Tailscale" };
            for (int i = 0; i < names.Length; i++)
            {
                Label lblName = new Label();
                lblName.Text = names[i];
                lblName.Font = nameFont;
                lblName.Dock = DockStyle.Fill;
                lblName.TextAlign = ContentAlignment.MiddleLeft;
                lblName.ForeColor = Color.WhiteSmoke;
                tblStatus.Controls.Add(lblName, 0, i);

                Label lblVal = new Label();
                lblVal.Text = "-";
                lblVal.Font = valFont;
                lblVal.Dock = DockStyle.Fill;
                lblVal.TextAlign = ContentAlignment.MiddleLeft;
                lblVal.ForeColor = Color.WhiteSmoke;
                tblStatus.Controls.Add(lblVal, 1, i);
                statusLabels[names[i]] = lblVal;
            }

            // 3. 按钮面板
            btnPanel = new FlowLayoutPanel();
            btnPanel.Dock = DockStyle.Top;
            btnPanel.Height = 88;
            btnPanel.Padding = new Padding(10, 10, 10, 4);
            btnPanel.AutoScroll = true;
            btnPanel.BackColor = Color.FromArgb(26, 30, 42);

            ToolTip tip = new ToolTip();

            Action<string, int, EventHandler, string, Color> addButton = (text, width, onClick, tipText, border) =>
            {
                Button b = new Button();
                b.Text = text;
                b.Width = width;
                b.Height = 30;
                b.Margin = new Padding(0, 0, 6, 6);
                b.FlatStyle = FlatStyle.Flat;
                b.FlatAppearance.BorderColor = border == Color.Empty ? Color.FromArgb(70, 80, 100) : border;
                b.BackColor = Color.FromArgb(42, 48, 64);
                b.ForeColor = Color.WhiteSmoke;
                b.Click += onClick;
                if (!string.IsNullOrEmpty(tipText)) tip.SetToolTip(b, tipText);
                btnPanel.Controls.Add(b);
            };

            addButton("启动", 76, (s, e) => SendAction("start", "启动 dsh"), "启动 watchdog，快速探测 180 秒", Color.Empty);
            addButton("停止", 76, (s, e) =>
            {
                if (MessageBox.Show("确认停止 DeepSeek Harness 与 watchdog 服务?", "停止 dsh", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
                {
                    SendAction("stop", "停止 dsh");
                }
            }, "停止端口 3080 进程链与 watchdog 服务", Color.FromArgb(180, 70, 70));

            addButton("重启", 76, (s, e) => SendAction("restart", "重启 dsh"), "先停止端口 3080 进程链，再启动 watchdog", Color.Empty);
            addButton("打开 Web UI", 104, (s, e) => OpenWebUi(), "浏览器打开 http://127.0.0.1:3080", Color.Empty);
            addButton("查看日志", 84, (s, e) => ShowRecentLogs(), "显示 watchdog 与 dsh-web 最近日志", Color.Empty);
            addButton("刷新", 72, (s, e) => { ForceRefresh(); AddLog("状态已刷新 (F5)"); }, "刷新状态 (F5)", Color.Empty);
            addButton("配置目录", 84, (s, e) => OpenFolder(settings.DshHome), "打开 " + settings.DshHome, Color.Empty);
            addButton("复制诊断", 84, (s, e) => CopyDiagnostics(), "复制当前状态与关键路径，便于反馈问题", Color.Empty);
            addButton("远程体检", 88, (s, e) => SendAction("remote-health", "远程健康检查"), "只读检查本机 Web、Tailscale、Serve 和 Tailnet HTTPS；不验证移动端会话", Color.Empty);
            addButton("更新预检", 88, (s, e) => SendAction("update-preflight", "更新预检"), "只读检查活跃 WSL 工作树、远端 HEAD 和代码回退锚点；不执行更新", Color.Empty);
            addButton("⚙ 设置", 84, (s, e) => OpenSettingsDialog(), "打开控制台设置：自定义背景图、尺寸、自动搜索功能目录等", Color.FromArgb(70, 130, 90));

            // 4. 日志面板
            logGroup = new GroupBox();
            logGroup.Text = "日志 / 输出";
            logGroup.Dock = DockStyle.Fill;
            logGroup.Padding = new Padding(8);
            logGroup.ForeColor = Color.WhiteSmoke;
            logGroup.BackColor = Color.FromArgb(32, 38, 52);

            logBox = new RichTextBox();
            logBox.Dock = DockStyle.Fill;
            logBox.ReadOnly = true;
            logBox.BackColor = Color.FromArgb(24, 26, 36);
            logBox.ForeColor = Color.WhiteSmoke;
            logBox.Font = new Font("Consolas", 9.5f);
            logBox.BorderStyle = BorderStyle.None;

            ContextMenuStrip logMenu = new ContextMenuStrip();
            logMenu.Items.Add("复制选中", null, (s, e) => { if (logBox.SelectionLength > 0) logBox.Copy(); else if (!string.IsNullOrEmpty(logBox.Text)) Clipboard.SetText(logBox.Text); });
            logMenu.Items.Add("全选", null, (s, e) => logBox.SelectAll());
            logMenu.Items.Add("清空", null, (s, e) => logBox.Clear());
            logBox.ContextMenuStrip = logMenu;
            logGroup.Controls.Add(logBox);

            // 5. 底部状态栏
            statusStrip = new StatusStrip();
            statusStrip.Dock = DockStyle.Bottom;
            statusStrip.BackColor = Color.FromArgb(20, 24, 36);
            statusStrip.ForeColor = Color.WhiteSmoke;

            refreshLabel = new ToolStripStatusLabel();
            refreshLabel.Text = "最后刷新: -";
            refreshLabel.ForeColor = Color.WhiteSmoke;
            statusStrip.Items.Add(refreshLabel);

            // 控件装配顺序 (Docking)
            this.Controls.Add(logGroup);
            this.Controls.Add(btnPanel);
            this.Controls.Add(statusGroup);
            this.Controls.Add(statusStrip);
            this.Controls.Add(bannerBox);

            // 确保日志区在顶层正确填充
            this.Controls.SetChildIndex(logGroup, 0);

            // 快捷键
            this.KeyDown += (s, e) =>
            {
                if (e.KeyCode == Keys.F5)
                {
                    ForceRefresh();
                    AddLog("状态已刷新 (F5)");
                    e.SuppressKeyPress = true;
                }
                else if (e.Control && e.KeyCode == Keys.L)
                {
                    logBox.Clear();
                    AddLog("日志已清空 (Ctrl+L)");
                    e.SuppressKeyPress = true;
                }
                else if ((e.Control && e.KeyCode == Keys.S) || (e.Alt && e.KeyCode == Keys.S))
                {
                    OpenSettingsDialog();
                    e.SuppressKeyPress = true;
                }
            };

            // 轮询定时器
            pollTimer = new System.Windows.Forms.Timer();
            pollTimer.Interval = 1000;
            pollTimer.Tick += (s, e) =>
            {
                UpdateStatus();
                ReadActionResults();
            };
            pollTimer.Start();

            this.Shown += (s, e) =>
            {
                if(bannerBox.Image == null && settings.BannerHeight > 0 && !string.IsNullOrEmpty(settings.BannerImagePath))
                {
                    ApplyBannerImage();
                }
                UpdateStatus();
                StartStatusPoller();
                AddLog("dsh 控制台已就绪");
            };

            this.FormClosed += (s, e) =>
            {
                try
                {
                    if (this.WindowState == FormWindowState.Normal)
                    {
                        settings.WindowWidth = this.ClientSize.Width;
                        settings.WindowHeight = this.ClientSize.Height;
                        settings.Save();
                    }
                }
                catch { }
                try
                {
                    if (pollerProcess != null && !pollerProcess.HasExited)
                    {
                        pollerProcess.Kill();
                    }
                }
                catch { }
                CleanTempFiles();
            };
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            if(bannerBox.Image == null && settings.BannerHeight > 0 && !string.IsNullOrEmpty(settings.BannerImagePath))
            {
                ApplyBannerImage();
            }
        }

        private void ApplyBannerSizeMode()
        {
            if (settings.BannerSizeMode == "Stretch") bannerBox.SizeMode = PictureBoxSizeMode.StretchImage;
            else if (settings.BannerSizeMode == "Center") bannerBox.SizeMode = PictureBoxSizeMode.CenterImage;
            else bannerBox.SizeMode = PictureBoxSizeMode.Zoom;
        }

        private void ApplyBannerImage()
        {
            if(settings.BannerHeight <= 0 || string.IsNullOrEmpty(settings.BannerImagePath) || !File.Exists(settings.BannerImagePath))
            {
                if(bannerBox.Image != null)
                {
                    Image old = bannerBox.Image;
                    bannerBox.Image = null;
                    old.Dispose();
                }
                bannerBox.Visible = settings.BannerHeight > 0;
                return;
            }

            string imgPath = settings.BannerImagePath;
            int bannerH = settings.BannerHeight;

            ThreadPool.QueueUserWorkItem((state) =>
            {
                try
                {
                    if(!File.Exists(imgPath))
                    {
                        return;
                    }
                    byte[] bytes = File.ReadAllBytes(imgPath);
                    Bitmap bmp;
                    using(MemoryStream ms = new MemoryStream(bytes))
                    {
                        using(Image orig = Image.FromStream(ms))
                        {
                            bmp = new Bitmap(orig);
                        }
                    }

                    // 等待窗口句柄创建就绪 (最多等待 5 秒)
                    int waited = 0;
                    while(!this.IsDisposed && !this.IsHandleCreated && waited < 5000)
                    {
                        Thread.Sleep(20);
                        waited += 20;
                    }

                    if(!this.IsDisposed && this.IsHandleCreated)
                    {
                        this.BeginInvoke(new Action(() =>
                        {
                            try
                            {
                                if(!bannerBox.IsDisposed)
                                {
                                    if(bannerBox.Image != null)
                                    {
                                        Image old = bannerBox.Image;
                                        bannerBox.Image = null;
                                        old.Dispose();
                                    }
                                    bannerBox.Image = bmp;
                                    bannerBox.Visible = bannerH > 0;
                                    bannerBox.Invalidate();
                                }
                                else
                                {
                                    bmp.Dispose();
                                }
                            }
                            catch
                            {
                                bmp.Dispose();
                            }
                        }));
                    }
                    else
                    {
                        bmp.Dispose();
                    }
                }
                catch { }
            });
        }

        private void OpenSettingsDialog()
        {
            string previousRoot = settings.HarnessRoot;
            string previousHome = settings.DshHome;
            using (SettingsForm sf = new SettingsForm(this.settings))
            {
                if (sf.ShowDialog(this) == DialogResult.OK && sf.SettingsChanged)
                {
                    this.settings = GuiSettings.Load();
                    bannerBox.Height = settings.BannerHeight;
                    bannerBox.Visible = settings.BannerHeight > 0;
                    ApplyBannerSizeMode();
                    ApplyBannerImage();

                    int minH = settings.BannerHeight + 520;
                    if (this.ClientSize.Height < minH)
                    {
                        this.ClientSize = new Size(this.ClientSize.Width, minH);
                    }
                    if (!string.Equals(previousRoot, settings.HarnessRoot, StringComparison.OrdinalIgnoreCase) ||
                        !string.Equals(previousHome, settings.DshHome, StringComparison.OrdinalIgnoreCase))
                    {
                        RestartStatusPoller();
                    }
                    AddLog("⚙ 设置已更新并生效");
                }
            }
        }

        private void SetStatusText(string key, string text, Color color)
        {
            Label lbl;
            if (statusLabels.TryGetValue(key, out lbl))
            {
                lbl.Text = text;
                lbl.ForeColor = color;
            }
        }

        private void ShowStatusUnavailable(string reason)
        {
            SetStatusText("web", "状态未知 (" + reason + ")", Color.DarkOrange);
            SetStatusText("watchdog", "状态未知", Color.DarkOrange);
            SetStatusText("WSL", "Unknown (虚拟 linux)", Color.DarkOrange);
            SetStatusText("Tailscale", "状态未知", Color.DarkOrange);
            refreshLabel.Text = "状态未更新: " + reason;
            lastStatusRaw = "";
        }

        private void UpdateStatus()
        {
            try
            {
                if (!File.Exists(StatusFile))
                {
                    ShowStatusUnavailable("等待轮询");
                    return;
                }

                TimeSpan age = DateTime.UtcNow - File.GetLastWriteTimeUtc(StatusFile);
                if (age.TotalSeconds > StatusMaxAgeSeconds || age.TotalSeconds < -5)
                {
                    ShowStatusUnavailable("轮询数据过期");
                    return;
                }

                string raw = File.ReadAllText(StatusFile, Encoding.UTF8);
                if (string.IsNullOrEmpty(raw))
                {
                    ShowStatusUnavailable("轮询数据为空");
                    return;
                }
                if (raw == lastStatusRaw) return;
                lastStatusRaw = raw;

                JavaScriptSerializer js = new JavaScriptSerializer();
                Dictionary<string, object> snap = js.Deserialize<Dictionary<string, object>>(raw);
                if (snap == null)
                {
                    ShowStatusUnavailable("轮询数据无效");
                    return;
                }

                // 活动日志
                if (snap.ContainsKey("activityLogTail") && snap["activityLogTail"] is System.Collections.IEnumerable)
                {
                    foreach (object item in (System.Collections.IEnumerable)snap["activityLogTail"])
                    {
                        if (item != null) AddLog(item.ToString());
                    }
                }

                // Web/Watchdog 日志
                if (!logTailReady)
                {
                    if (snap.ContainsKey("webLogTail") || snap.ContainsKey("watchdogLogTail")) logTailReady = true;
                }
                else
                {
                    if (snap.ContainsKey("webLogTail") && snap["webLogTail"] is System.Collections.IEnumerable)
                    {
                        foreach (object item in (System.Collections.IEnumerable)snap["webLogTail"])
                        {
                            if (item != null) AddLog("[web] " + item.ToString());
                        }
                    }
                    if (snap.ContainsKey("watchdogLogTail") && snap["watchdogLogTail"] is System.Collections.IEnumerable)
                    {
                        foreach (object item in (System.Collections.IEnumerable)snap["watchdogLogTail"])
                        {
                            if (item != null) AddLog("[watchdog] " + item.ToString());
                        }
                    }
                }

                // web
                bool webUp = snap.ContainsKey("webUp") && Convert.ToBoolean(snap["webUp"]);
                string http = snap.ContainsKey("http") ? snap["http"].ToString() : "";
                bool webPortOpen = snap.ContainsKey("webPortOpen") ? Convert.ToBoolean(snap["webPortOpen"]) : webUp;
                string webPid = snap.ContainsKey("webPid") && snap["webPid"] != null ? snap["webPid"].ToString() : "";
                if (webUp && http == "HTTP 200")
                {
                    string txt = "运行中 (" + http + (string.IsNullOrEmpty(webPid) ? "" : ", 端口 PID " + webPid) + ")";
                    SetStatusText("web", txt, Color.ForestGreen);
                }
                else if (webPortOpen)
                {
                    string txt = "未就绪 (" + (string.IsNullOrEmpty(http) ? "端口有监听" : http) + ")";
                    SetStatusText("web", txt, Color.DarkOrange);
                }
                else
                {
                    SetStatusText("web", "未运行", Color.Firebrick);
                }

                // watchdog
                string wdPids = snap.ContainsKey("watchdogPids") && snap["watchdogPids"] != null ? snap["watchdogPids"].ToString() : "";
                if (!string.IsNullOrEmpty(wdPids))
                {
                    SetStatusText("watchdog", "运行中 (PID " + wdPids + ")", Color.ForestGreen);
                }
                else
                {
                    SetStatusText("watchdog", "未运行", Color.Firebrick);
                }

                // WSL
                string wsl = snap.ContainsKey("wsl") && snap["wsl"] != null ? snap["wsl"].ToString() : "Unknown";
                if (wsl == "Running") SetStatusText("WSL", "Running (虚拟 linux)", Color.ForestGreen);
                else SetStatusText("WSL", wsl + " (虚拟 linux)", Color.DarkOrange);

                // Dsh Home
                bool hasHome = snap.ContainsKey("dshHome") && Convert.ToBoolean(snap["dshHome"]);
                bool hasProfile = snap.ContainsKey("dshProfile") && Convert.ToBoolean(snap["dshProfile"]);
                if (hasHome)
                {
                    if (hasProfile) SetStatusText("dsh home", settings.DshHome + " (web profile 已配置)", Color.ForestGreen);
                    else SetStatusText("dsh home", settings.DshHome + " (web profile 缺失)", Color.DarkOrange);
                }
                else
                {
                    SetStatusText("dsh home", settings.DshHome + " (缺失)", Color.Firebrick);
                }

                // Tailscale
                string ts = snap.ContainsKey("tailscale") && snap["tailscale"] != null ? snap["tailscale"].ToString() : "";
                string tsIp = snap.ContainsKey("tailscaleIp") && snap["tailscaleIp"] != null ? snap["tailscaleIp"].ToString() : "";
                string tsServe = snap.ContainsKey("tailscaleServe") && snap["tailscaleServe"] != null ? snap["tailscaleServe"].ToString() : "";
                if (!string.IsNullOrEmpty(ts))
                {
                    if (ts.StartsWith("已连接") && !string.IsNullOrWhiteSpace(tsIp))
                    {
                        string txt = ts;
                        if (tsServe.StartsWith("https://")) txt += " | " + tsServe;
                        SetStatusText("Tailscale", txt, Color.ForestGreen);
                    }
                    else if (ts.StartsWith("已连接")) SetStatusText("Tailscale", "状态不可用 (无 IP)", Color.DarkOrange);
                    else if (ts == "未登录") SetStatusText("Tailscale", "未登录", Color.DarkOrange);
                    else if (ts == "未安装") SetStatusText("Tailscale", "未安装", Color.Firebrick);
                    else SetStatusText("Tailscale", ts, Color.DarkOrange);
                }

                string time = snap.ContainsKey("time") && snap["time"] != null ? snap["time"].ToString() : "";
                refreshLabel.Text = string.Format("最后刷新: {0} | 端口: 3080", time);
            }
            catch (Exception ex)
            {
                ShowStatusUnavailable("读取异常");
                refreshLabel.Text = "状态读取异常: " + ex.Message;
            }
        }

        private void RestartStatusPoller()
        {
            try
            {
                if (pollerProcess != null && !pollerProcess.HasExited)
                {
                    pollerProcess.Kill();
                    pollerProcess.WaitForExit(3000);
                }
            }
            catch { }
            pollerProcess = null;
            try
            {
                if (File.Exists(PollerPidFile)) File.Delete(PollerPidFile);
                if (File.Exists(StatusFile)) File.Delete(StatusFile);
            }
            catch { }
            ShowStatusUnavailable("等待轮询");
            StartStatusPoller();
        }

        private void StartStatusPoller()
        {
            try
            {
                if (pollerProcess != null && !pollerProcess.HasExited) return;
                if (File.Exists(PollerPidFile))
                {
                    string rawPid = File.ReadAllText(PollerPidFile).Trim();
                    int pid;
                    if (int.TryParse(rawPid, out pid))
                    {
                        Process existing = Process.GetProcessById(pid);
                        if (existing != null && !existing.HasExited)
                        {
                            pollerProcess = existing;
                            ForceRefresh();
                            return;
                        }
                    }
                }
            }
            catch { }

            // 启动 Poller
            try
            {
                string baseDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\', '/');
                string pollerPath = Path.Combine(baseDir, "dsh-gui-poller.ps1");
                if (!File.Exists(pollerPath))
                {
                    pollerPath = Path.Combine(settings.HarnessRoot, "packages", "selfuse", "control-gui", "dsh-gui-poller.ps1");
                }
                if (!File.Exists(pollerPath))
                {
                    pollerPath = Path.Combine(settings.HarnessRoot, "dsh-gui-poller.ps1");
                }
                if (!File.Exists(pollerPath))
                {
                    pollerPath = PollerFile;
                }

                string watchdogFile = Path.Combine(settings.HarnessRoot, "dsh-watchdog.ps1");
                string webLog = Path.Combine(settings.HarnessRoot, "dsh-web.log");
                string watchdogLog = Path.Combine(settings.HarnessRoot, "dsh-watchdog.log");
                string dshProfile = Path.Combine(settings.DshHome, @"profiles\web");

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = string.Format(
                    "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{0}\" -StatusFile \"{1}\" -TriggerFile \"{2}\" -CmdFile \"{3}\" -ResultPrefix \"{4}\" -ActivityFile \"{5}\" -WebUrl \"http://127.0.0.1:3080\" -WebPort 3080 -DshHome \"{6}\" -DshProfile \"{7}\" -WatchdogFile \"{8}\" -WebLog \"{9}\" -WatchdogLog \"{10}\" -HarnessRoot \"{11}\" -PollerPidFile \"{12}\" -Interval 3",
                    pollerPath, StatusFile, TriggerFile, CmdFile, ResultPrefix, ActivityFile,
                    settings.DshHome, dshProfile, watchdogFile, webLog, watchdogLog, settings.HarnessRoot, PollerPidFile
                );
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                pollerProcess = Process.Start(psi);
            }
            catch { }
        }

        private void ForceRefresh()
        {
            try
            {
                File.WriteAllText(TriggerFile, DateTime.Now.Ticks.ToString());
            }
            catch { }
        }

        private void SendAction(string action, string label)
        {
            try
            {
                string id = Guid.NewGuid().ToString("N");
                Dictionary<string, string> cmd = new Dictionary<string, string>();
                cmd["action"] = action;
                cmd["id"] = id;
                JavaScriptSerializer js = new JavaScriptSerializer();
                File.WriteAllText(CmdFile, js.Serialize(cmd), Encoding.UTF8);
                AddLog("==> " + label + " 命令已发送");
            }
            catch (Exception ex)
            {
                AddLog("发送命令失败: " + ex.Message);
            }
        }

        private void ReadActionResults()
        {
            try
            {
                string[] files = Directory.GetFiles(TempDir, "dsh-gui-result-*.json");
                JavaScriptSerializer js = new JavaScriptSerializer();
                foreach (string file in files)
                {
                    try
                    {
                        string content = File.ReadAllText(file, Encoding.UTF8);
                        Dictionary<string, object> res = js.Deserialize<Dictionary<string, object>>(content);
                        if (res != null && res.ContainsKey("lines") && res["lines"] is System.Collections.IEnumerable)
                        {
                            foreach (object line in (System.Collections.IEnumerable)res["lines"])
                            {
                                if (line != null) AddLog(line.ToString());
                            }
                        }
                    }
                    catch { }
                    try { File.Delete(file); } catch { }
                }
            }
            catch { }
        }

        private void AddLog(string msg)
        {
            if (logBox.IsDisposed) return;
            if (logBox.TextLength > 300000)
            {
                logBox.Select(0, 100000);
                logBox.SelectedText = "";
            }
            string time = DateTime.Now.ToString("HH:mm:ss");
            logBox.AppendText(string.Format("{0}  {1}\r\n", time, msg));
            logBox.SelectionStart = logBox.TextLength;
            logBox.ScrollToCaret();
        }

        private void OpenWebUi()
        {
            string url = "http://127.0.0.1:3080";
            string logPath = Path.Combine(settings.HarnessRoot, "dsh-web.log");
            if (File.Exists(logPath))
            {
                try
                {
                    string[] lines = File.ReadAllLines(logPath, Encoding.UTF8);
                    for (int i = lines.Length - 1; i >= Math.Max(0, lines.Length - 300); i--)
                    {
                        int idx = lines[i].IndexOf("http://127.0.0.1:3080/?token=");
                        if (idx >= 0)
                        {
                            int end = lines[i].IndexOfAny(new char[] { ' ', '\t', '\r', '\n', ')' }, idx);
                            url = end > 0 ? lines[i].Substring(idx, end - idx) : lines[i].Substring(idx);
                            break;
                        }
                    }
                }
                catch { }
            }
            try
            {
                Process.Start(url);
                AddLog("==> 已打开 " + url);
            }
            catch (Exception ex)
            {
                AddLog("打开浏览器失败: " + ex.Message);
            }
        }

        private void ShowRecentLogs()
        {
            AddLog("==> 最近日志输出");
            string[] logs = new string[] { Path.Combine(settings.HarnessRoot, "dsh-watchdog.log"), Path.Combine(settings.HarnessRoot, "dsh-web.log") };
            foreach (string log in logs)
            {
                if (File.Exists(log))
                {
                    AddLog("--- " + Path.GetFileName(log) + " ---");
                    try
                    {
                        string[] lines = File.ReadAllLines(log, Encoding.UTF8);
                        int count = Math.Min(8, lines.Length);
                        for (int i = lines.Length - count; i < lines.Length; i++)
                        {
                            logBox.AppendText(lines[i] + "\r\n");
                        }
                    }
                    catch { }
                }
            }
            logBox.SelectionStart = logBox.TextLength;
            logBox.ScrollToCaret();
        }

        private void OpenFolder(string folder)
        {
            if (Directory.Exists(folder))
            {
                try
                {
                    Process.Start("explorer.exe", "\"" + folder + "\"");
                    AddLog("==> 已打开目录 " + folder);
                }
                catch (Exception ex)
                {
                    AddLog("打开目录失败: " + ex.Message);
                }
            }
            else
            {
                AddLog("目录不存在: " + folder);
            }
        }

        private void CopyDiagnostics()
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("dsh 控制台诊断 " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
            foreach (var kv in statusLabels)
            {
                sb.AppendLine(string.Format("{0}: {1}", kv.Key, kv.Value.Text));
            }
            sb.AppendLine("HarnessRoot: " + settings.HarnessRoot);
            sb.AppendLine("DshHome: " + settings.DshHome);
            sb.AppendLine("BannerImagePath: " + settings.BannerImagePath);
            sb.AppendLine("BannerHeight: " + settings.BannerHeight);
            try
            {
                Clipboard.SetText(sb.ToString());
                AddLog("诊断信息已复制到剪贴板");
            }
            catch (Exception ex)
            {
                AddLog("复制剪贴板失败: " + ex.Message);
            }
        }

        private void CleanTempFiles()
        {
            try
            {
                string[] files = Directory.GetFiles(TempDir, "dsh-gui-result-*.json");
                foreach (string f in files) { try { File.Delete(f); } catch { } }
                if (File.Exists(TriggerFile)) File.Delete(TriggerFile);
                if (File.Exists(CmdFile)) File.Delete(CmdFile);
                if (File.Exists(ActivityFile)) File.Delete(ActivityFile);
                if (File.Exists(PollerPidFile)) File.Delete(PollerPidFile);
            }
            catch { }
        }
    }

    internal static class Program
    {
        private static bool IsAdministrator()
        {
            try
            {
                var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
                var principal = new System.Security.Principal.WindowsPrincipal(identity);
                return principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
            }
            catch
            {
                return false;
            }
        }

        [STAThread]
        private static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            bool smokeTest = false;
            bool noElevate = false;
            foreach (string arg in args)
            {
                if (arg.Equals("-SmokeTest", StringComparison.OrdinalIgnoreCase))
                {
                    smokeTest = true;
                }
                if (arg.Equals("-NoElevate", StringComparison.OrdinalIgnoreCase))
                {
                    noElevate = true;
                }
            }

            if (!smokeTest && !noElevate && !IsAdministrator())
            {
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = Application.ExecutablePath;
                    psi.Arguments = string.Join(" ", args);
                    psi.Verb = "runas";
                    psi.UseShellExecute = true;
                    Process.Start(psi);
                    return;
                }
                catch
                {
                    // User declined UAC, continue as regular user
                }
            }

            GuiSettings settings = GuiSettings.Load();
            Application.Run(new MainForm(settings, smokeTest));
        }
    }
}
