// Single-file Windows launcher for Half-Life 2: Kart.
//
// The release zip (the game's code, Godot and Python; no Valve content) is
// embedded in this exe. The first run unpacks it to
// %LOCALAPPDATA%\HL2Kart\<version>; every run then starts the game from there,
// and the game's own first-start screen builds the Half-Life content from the
// player's Steam games. Built by tools/package_release.py with the C# compiler
// that comes with Windows (.NET Framework 4.8), so it runs without installing
// anything.
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

static class Launcher
{
    const string Version = "@VERSION@";
    const string Title = "Half-Life 2: Kart";

    [STAThread]
    static int Main()
    {
        string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                                   "HL2Kart", Version);
        string marker = Path.Combine(root, ".unpacked");
        if (!File.Exists(marker) && !Unpack(root, marker))
            return 1;
        string godot = Path.Combine(root, "runtime", "godot", "godot.exe");
        try
        {
            var psi = new ProcessStartInfo(godot, "--path \"" + root + "\"");
            psi.WorkingDirectory = root;
            psi.UseShellExecute = false;
            Process.Start(psi);
        }
        catch (Exception e)
        {
            MessageBox.Show("Could not start the game:\n" + e.Message, Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        return 0;
    }

    // A small window with a progress bar while the files are unpacked.
    static bool Unpack(string root, string marker)
    {
        Application.EnableVisualStyles();
        var form = new Form();
        form.Text = Title;
        form.ClientSize = new System.Drawing.Size(500, 96);
        form.FormBorderStyle = FormBorderStyle.FixedDialog;
        form.MaximizeBox = false;
        form.MinimizeBox = false;
        form.StartPosition = FormStartPosition.CenterScreen;
        var label = new Label();
        label.Text = "Unpacking " + Title + " v" + Version + " (first run only)...";
        label.SetBounds(16, 16, 468, 22);
        var bar = new ProgressBar();
        bar.SetBounds(16, 48, 468, 24);
        form.Controls.Add(label);
        form.Controls.Add(bar);
        Exception error = null;
        form.Shown += delegate
        {
            var worker = new Thread(delegate ()
            {
                try
                {
                    Extract(root, delegate (int done, int total)
                    {
                        form.BeginInvoke((Action)delegate { bar.Maximum = total; bar.Value = done; });
                    });
                    File.WriteAllText(marker, Version);
                }
                catch (Exception e)
                {
                    error = e;
                }
                form.BeginInvoke((Action)delegate { form.Close(); });
            });
            worker.IsBackground = true;
            worker.Start();
        };
        Application.Run(form);
        if (error != null)
        {
            MessageBox.Show("Could not unpack the game to " + root + ":\n" + error.Message, Title,
                            MessageBoxButtons.OK, MessageBoxIcon.Error);
            return false;
        }
        return true;
    }

    static void Extract(string root, Action<int, int> progress)
    {
        string full = Path.GetFullPath(root) + Path.DirectorySeparatorChar;
        using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
        using (var zip = new ZipArchive(s, ZipArchiveMode.Read))
        {
            int total = zip.Entries.Count;
            int done = 0;
            foreach (ZipArchiveEntry entry in zip.Entries)
            {
                // entries are stored as "HL2Kart/<path>"
                string rel = entry.FullName;
                int slash = rel.IndexOf('/');
                if (slash >= 0)
                    rel = rel.Substring(slash + 1);
                done++;
                if (rel.Length == 0)
                    continue;
                string dest = Path.GetFullPath(Path.Combine(root, rel));
                if (!dest.StartsWith(full, StringComparison.OrdinalIgnoreCase))
                    throw new IOException("unexpected path in the archive: " + entry.FullName);
                if (rel.EndsWith("/"))
                {
                    Directory.CreateDirectory(dest);
                }
                else
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(dest));
                    entry.ExtractToFile(dest, true);
                }
                if (done % 16 == 0 || done == total)
                    progress(done, total);
            }
        }
    }
}
