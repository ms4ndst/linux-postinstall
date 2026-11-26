# ClamAV On-Access Scanning on Fedora

Nov 2, 2026 · @Magnus

## Overview

On Fedora, real-time scanning needs `clamonacc` running with `--fdpass`; the stock unit omits that flag, so every file under a 700-mode home folder fails with "Permission denied".

`clamd@scan` is the background daemon that holds the signatures and does the scanning. `clamonacc` is a separate root process that watches paths through fanotify and hands each opened file to `clamd`. With `--fdpass` it passes an already-open file descriptor, so `clamd` (running as user `clamscan`) never needs read access to your home folder.

Status: steps 1–5 verified on Fedora (the override is active); the final EICAR detection after the fix is still to be confirmed.

## 1. Prerequisites

The daemon must be installed, configured and running before on-access scanning can work.

```bash
sudo dnf install clamav clamd clamav-update
sudo freshclam
sudo systemctl enable --now clamav-freshclam

# Enable scan.conf and its local socket
sudo sed -i 's/^Example/#Example/' /etc/clamd.d/scan.conf
sudo sed -i 's|^#LocalSocket /run/clamd.scan/clamd.sock|LocalSocket /run/clamd.scan/clamd.sock|' /etc/clamd.d/scan.conf

# Let SELinux allow scanning
sudo setsebool -P antivirus_can_scan_system 1

sudo systemctl enable --now clamd@scan
```

The package on Fedora is `clamd`, not `clamav-daemon` (that is the Debian/Ubuntu name).

## 2. Configure on-access settings

Append the on-access block to `/etc/clamd.d/scan.conf`; watch `/home`, never `/`.

```bash
sudo tee -a /etc/clamd.d/scan.conf >/dev/null <<'EOF'

# --- On-access scanning ---
OnAccessIncludePath /home
OnAccessExcludeUname clamscan
OnAccessExtraScanning yes
OnAccessPrevention no
EOF
```

| Setting | Why |
| --- | --- |
| `OnAccessIncludePath /home` | Paths to watch, one line each. Watching `/` is heavy and can cause scan loops. |
| `OnAccessExcludeUname clamscan` | Stops clamd scanning its own reads. Confirm the user with `grep ^User /etc/clamd.d/scan.conf`. |
| `OnAccessExtraScanning yes` | Also scans files when they are created or moved. |
| `OnAccessPrevention no` | Detect only. `yes` blocks infected files, but file access can hang if clamd stops — enable only after testing. |

## 3. Raise the inotify watch limit

The default limit is too low for a large `/home`; raise it to 524288.

```bash
echo 'fs.inotify.max_user_watches=524288' | sudo tee /etc/sysctl.d/90-clamonacc.conf
sudo sysctl --system
```

## 4. Fix: add --fdpass with a systemd override

Fedora's stock unit runs `clamonacc -F --config-file=/etc/clamd.d/scan.conf` without `--fdpass`, so clamd tries to open paths it cannot read.

Check the unit:

```bash
systemctl cat clamav-clamonacc | grep ExecStart
```

Add the override (the empty `ExecStart=` clears the original line):

```bash
sudo mkdir -p /etc/systemd/system/clamav-clamonacc.service.d
sudo tee /etc/systemd/system/clamav-clamonacc.service.d/override.conf >/dev/null <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/sbin/clamonacc -F --fdpass --config-file=/etc/clamd.d/scan.conf
EOF
sudo systemctl daemon-reload
```

Do not "fix" this with `User root` in `scan.conf`: it works, but a clamd parser bug would then give an attacker root.

## 5. Exclude noisy paths

Exclude caches and constantly rewritten log folders to cut CPU load and log noise. Replace `<user>` with your username.

```bash
echo 'OnAccessExcludePath /home/<user>/.cache' | sudo tee -a /etc/clamd.d/scan.conf
echo 'OnAccessExcludePath /home/<user>/.vibe/logs' | sudo tee -a /etc/clamd.d/scan.conf
```

If you develop under `/home`, consider excluding build folders such as `node_modules` too.

## 6. Start and verify

Restart both services, confirm `--fdpass` is active, then trigger the EICAR test file.

```bash
sudo systemctl restart clamd@scan
sudo systemctl enable --now clamav-clamonacc
sudo systemctl restart clamav-clamonacc

# Must print "fdpass"
systemctl show clamav-clamonacc -p ExecStart | grep -o fdpass

# EICAR is a harmless test signature every antivirus detects
curl -s https://secure.eicar.org/eicar.com.txt -o ~/eicar.txt
cat ~/eicar.txt
sleep 2
sudo journalctl -u clamav-clamonacc --since "-2min" --no-pager
```

Expected: a line ending in `Eicar-Signature FOUND`, and no "Permission denied" lines from the new process. Then remove the file with `rm ~/eicar.txt`.

When reading the journal, check the PID: errors logged before the restart come from the old process and say nothing about the fix.

## 7. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `File path check failure: Permission denied` for files in `/home` | clamonacc sends paths, not file descriptors; clamd (user `clamscan`) cannot read 700-mode home folders | Add `--fdpass` via the override in step 4 |
| Same error with `--fdpass` active | SELinux denying the descriptor hand-off | Run `sudo ausearch -m avc -ts recent \| grep -i clam` and `getsebool antivirus_can_scan_system`; review denials before any `audit2allow` module |
| Flood of errors from `~/.cache` or log folders | Files rewritten constantly | Add `OnAccessExcludePath` lines (step 5) |
| Watches fail on large `/home` | inotify limit too low | Step 3 |
| `Main process exited, status=9/KILL` on stop | clamonacc often does not stop cleanly; systemd kills it | Harmless |
| clamd will not start, "Example" in log | Stock config still disabled | Comment out the `Example` line (step 1) |

## 8. Cost and cautions

Expect roughly 2.5 GB of RAM in total: clamonacc peaked at 1.5 GB on the test machine, and clamd with signatures loaded uses about 1 GB more.

- On a laptop, a scheduled `clamscan` is the lighter alternative if real-time scanning is not required.
- File operations under watched paths get slower; exclude build and cache folders.
- Keep `OnAccessPrevention no` until detection is proven; blocking mode can hang file access if clamd stops.
