# moomu

A little companion that lives in your notch and runs your own Claude Code: chat, calls, agents and
group chats, memory, and a live view of the work it does. [moomu.app](https://moomu.app)

This repository holds moomu's installers and updates. The app checks here for new versions by itself.

## Install

**macOS** (Terminal):

```sh
curl -fsSL https://moomu.app/install | bash
```

**Windows** (PowerShell):

```powershell
irm https://moomu.app/install.ps1 | iex
```

Linux is coming soon.

The installer puts moomu in your Applications (macOS) or your user's programs (Windows, no admin needed), installs
[Claude Code](https://claude.com/claude-code) with Anthropic's own installer if you don't have it yet, and opens moomu.
You sign in to Claude Code inside moomu's first run, in Claude Code's own window: moomu never sees your login.

You can also download a build directly from [Releases](../../releases).

## Help

Questions and bug reports: hello@moomu.app
