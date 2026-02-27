# Discord Rich Presence — Setup Guide

Show your openchad activity on Discord with a single command.

---

## Quick Start (Recommended)

No Discord Developer account needed. Uses the official openchad app:

```bash
openchad discord enable
```

That's it. Presence updates the next time you start openchad.

---

## Advanced: Use Your Own Discord App

Want a custom name, logo, or Application ID? Create your own Discord app:

### Step 1: Create a Discord Application

1. Go to <https://discord.com/developers/applications>
2. Click **New Application**
3. Name it anything you like (e.g., `openchad`)
4. Click **Create**

### Step 2: Get Your Client ID

1. On the application page, go to **General Information**
2. Copy the **Application ID** — this is your Client ID
3. It looks like: `1234567890123456789` (17–20 digits)

### Step 3: Upload a Logo (Optional)

1. In your application, go to **Rich Presence → Art Assets**
2. Click **Add Image(s)**
3. Upload a square image (minimum 512×512 px recommended)
4. Set the key name to: `open_chad_logo`
5. Click **Save Changes**

### Step 4: Enable with Your Custom App

```bash
openchad discord enable --custom
```

The wizard will prompt for your Client ID, validate it, and write it to config.

---

## Managing Rich Presence

| Command | Effect |
|---------|--------|
| `openchad discord enable` | Enable with built-in default app (no prompt) |
| `openchad discord enable --custom` | Enable with your own Discord app (interactive) |
| `openchad discord disable` | Disable and remove presence |
| `openchad discord status` | Show current config, mode, and last update time |

---

## Privacy Notes

openchad's Rich Presence shows **only**:

- A rotating tagline (e.g., "Chadding hard")
- Session count (integer)
- Elapsed time (monotonic clock)
- A button linking to the openchad GitHub repo

**Nothing sensitive is ever transmitted** — no project names, file paths,
model names, credentials, or git remote URLs. All dynamic input is passed
through a sanitizer that redacts paths, tokens, and environment variables.

---

## WSL2 Setup

On WSL2, Discord runs on Windows but openchad runs in Linux. openchad automatically
bridges the gap using `socat` + `npiperelay.exe`. Install the two dependencies once:

```bash
# 1. Install socat (Linux side)
sudo apt install socat

# 2. Install npiperelay (Windows side, accessible from WSL)
go install github.com/jstarks/npiperelay@latest
# Ensure $GOPATH/bin is on PATH — add to ~/.bashrc or ~/.zshrc:
export PATH="$PATH:$(go env GOPATH)/bin"
```

After installing, the bridge starts automatically on the next `openchad` launch.
No additional configuration needed.

**Verify bridge status:**
```bash
openchad discord status   # shows Bridge: ready (PID ...)
openchad doctor           # section 7: WSL Discord IPC bridge
```

**Bridge log** (for troubleshooting):
```bash
cat "$OPEN_CHAD_CACHE_DIR/discord-bridge.log"
# or: cat /run/user/$(id -u)/open-chad/discord-bridge.log
```

---

## Troubleshooting

**Presence not showing?**
- Make sure Discord desktop app is running (not just web)
- Verify `discordPresence.enabled: true` in your config: `openchad discord status`
- Check debug log: `cat "$OPEN_CHAD_CACHE_DIR/discord.log"`
- On WSL2: check bridge status with `openchad discord status` and `openchad doctor`

**"Invalid Client ID" error?**
- Client IDs are 17–20 digit numbers
- Get it from discord.com/developers/applications → General Information → Application ID

**Rate limit warning in log?**
- Normal — openchad enforces its own 15-second rate limit to stay within Discord's spec

**WSL2: Bridge not starting?**
- Run `openchad doctor` to check socat and npiperelay.exe are on PATH
- Ensure `npiperelay.exe` is accessible from WSL (usually via `$GOPATH/bin`)
- Check bridge log: `cat "$OPEN_CHAD_CACHE_DIR/discord-bridge.log"`
