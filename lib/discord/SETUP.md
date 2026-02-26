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

## Troubleshooting

**Presence not showing?**
- Make sure Discord desktop app is running (not just web)
- Verify `discordPresence.enabled: true` in your config: `openchad discord status`
- Check debug log: `cat "$(openchad discord status | grep 'Debug log' | awk '{print $NF}')"`

**"Invalid Client ID" error?**
- Client IDs are 17–20 digit numbers
- Get it from discord.com/developers/applications → General Information → Application ID

**Rate limit warning in log?**
- Normal — openchad enforces its own 15-second rate limit to stay within Discord's spec
