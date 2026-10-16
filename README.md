# Baobab AI film tools — installer

The one-line installers for the studio's AI film tools. They need an invitation from the studio:
on their own they install standard tools (git, Python, ffmpeg, the GitHub and Google Cloud command
lines) and then stop at the GitHub sign-in.

**Windows 11** — in PowerShell:

```powershell
irm https://raw.githubusercontent.com/BaobabStudios/artist-install/main/install.ps1 | iex
```

**macOS 13 or later** — in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/BaobabStudios/artist-install/main/install.sh | bash
```

Safe to run again; a re-run repairs a half-finished install and never deletes anything.
