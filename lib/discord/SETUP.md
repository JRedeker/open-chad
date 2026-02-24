# Discord Rich Presence — Setup Guide

This guide walks you through creating a Discord application to power
open-chad's Rich Presence display.

---

## Step 1: Create a Discord Application

1. Go to <https://discord.com/developers/applications>
2. Click **New Application**
3. Name it **open-chad** (or anything you prefer)
4. Click **Create**

## Step 2: Get Your Client ID

1. On the application page, go to **General Information**
2. Copy the **Application ID** — this is your Client ID
3. It looks like: `1234567890123456789` (17–20 digits)

You'll enter this when running `open-chad discord enable`.

## Step 3: Upload the Logo (Large Image Asset)

1. In your application, go to **Rich Presence → Art Assets**
2. Click **Add Image(s)**
3. Upload a square image (minimum 512×512 px recommended)
4. Set the key name to: `open_chad_logo`
5. Click **Save Changes**

> **Alternative**: You can skip this step and use the GitHub avatar URL instead.
> open-chad will fall back to a default image if the asset key is not found.

## Step 4: Enable in open-chad

Run the setup wizard:

```bash
open-chad discord enable
```

The wizard will:
- Ask for your Client ID
- Validate the format
- Write the config to `~/.config/opencode/open-chad.json`
- Confirm Rich Presence is active

---

## Managing Rich Presence

| Command | Effect |
|---------|--------|
| `open-chad discord enable` | First-run wizard; or re-enable if disabled |
| `open-chad discord disable` | Disable and remove presence |
| `open-chad discord status` | Show current config and last update time |

---

## Privacy Notes

open-chad's Rich Presence shows **only**:

- A rotating tagline (e.g., "Chadding hard")
- Session count (integer)
- Elapsed time (monotonic clock)
- A button linking to the open-chad GitHub repo

**Nothing sensitive is ever transmitted** — no project names, file paths,
model names, credentials, or git remote URLs. All dynamic input is passed
through a sanitizer that redacts paths, tokens, and environment variables.

---

## Troubleshooting

**Presence not showing?**
- Make sure Discord desktop app is running (not just web)
- Verify `discordPresence.enabled: true` in your config
- Check debug log: `cat /tmp/open-chad-discord.log`

**"Invalid Client ID" error?**
- Client IDs are 17–20 digit numbers
- Get it from discord.com/developers/applications → General Information → Application ID

**Rate limit warning in log?**
- Normal — open-chad enforces its own 15-second rate limit to stay within Discord's spec
