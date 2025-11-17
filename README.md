# CouchCoder

CouchCoder is a personal SwiftUI iOS app that turns the Messages UI into a comfy remote terminal for your Mac. Each project living under the `PROJECTS_BASE_PATH` defined in `.env` appears as a “conversation.” Commands you type are sent to a persistent SSH shell that runs inside that project folder, and the live output streams back. Shortcut buttons let you run a full git add/commit/push or kick off a wireless `xcodebuild install`.

> ⚠️ This is a personal toy, not a production-ready remote IDE. Everything is hardcoded for one Mac + one iPhone. Share responsibly.

## iOS App Highlights

- Built for iOS 26 using SwiftUI
- Uses a vendored build of [SwiftSH](https://github.com/migueldeicaza/SwiftSH) to keep per-project SSH shells alive.
- Project list mimics Messages conversations (last preview) with swipe-to-hide and pin feature and an “eye” toggle for hidden repos.
- Shortcut bar buttons:
  - `Git Sync`: `git add . && git commit -m "couch vibes" && git push`
  - `Build & Install`: runs `xcodebuild -scheme <your scheme> -destination 'platform=iOS,id=<your-device-udid>' build install`

## Local Configuration (`.env`)

All sensitive values live in `CouchCoder/Config/.env`. The repo ships with placeholder values—replace them with your own or create `CouchCoder/Config/.env.local` (gitignored) to keep personal secrets out of version control. Values in `.env.local` override those in `.env`.

Required highlights:

- SSH connection: `SSH_HOST`, `SSH_PORT`, `SSH_USERNAME`
- Private key: either set `SSH_PRIVATE_KEY_PATH` to the file on disk or inline it via `SSH_PRIVATE_KEY` (wrap in quotes and escape newlines as `\n`)
- Deployment defaults: `PROJECTS_BASE_PATH`, `DEFAULT_AGENT`, `DEVICE_UDID`, `DEVELOPMENT_TEAM`, `GIT_ONE_LINER`
- Build signing helper: `KEYCHAIN_PASSWORD` (used to unlock your login keychain before running `xcodebuild install`)
- Persistence keys: `HIDDEN_PROJECTS_KEY`, `PINNED_PROJECTS_KEY`, `PINNED_PROJECTS_MAX_COUNT`, `PROJECT_ACCENT_COLORS_KEY`
- New-project defaults: `NEW_PROJECT_BUNDLE_PREFIX`, `NEW_PROJECT_DEPLOYMENT_TARGET`

Bundle identifiers, device IDs, and shell paths are no longer baked into Swift files, so feel free to publish the source without leaking your local setup.

### Where to Find Config Values

- **SSH host** – on your Mac, run `scutil --get LocalHostName` (produces something like `my-mac`) and append `.local`, or grab the hostname from System Settings → General → Sharing. Bonjour names (`your-mac.local`) are easiest because they track IP changes automatically.
- **SSH username** – usually your macOS short name. Confirm with `whoami` in Terminal.
- **Device UDID** – plug your iPhone into your Mac, open Finder, select the device from the sidebar, then click the serial number label to toggle through fields until UDID appears. Right-click → Copy UDID. (You can also use Xcode → Window → Devices & Simulators.)
- **Development Team ID** – open Xcode → Settings → Accounts, select your Apple ID, then look under “Team” for the 10-character identifier (or check your provisioning profile's `DEVELOPMENT_TEAM`).
- **Projects base path** – point at the parent directory that contains your repos. `pwd` inside that folder to copy the absolute path.

### Getting an SSH Private Key

**Option 1: Generate a new key pair (recommended)**

On your Mac, run:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/couchcoder_key -N ""
```

This creates:
- Private key: `~/.ssh/couchcoder_key` (point `SSH_PRIVATE_KEY_PATH` at this file in `.env`)
- Public key: `~/.ssh/couchcoder_key.pub` (add this to your Mac's authorized_keys)

Then add the public key to your Mac:
```bash
cat ~/.ssh/couchcoder_key.pub >> ~/.ssh/authorized_keys
```

**Option 2: Use an existing key**

If you already have an SSH key (check `~/.ssh/id_ed25519` or `~/.ssh/id_rsa`), you can use that:

```bash
# Inside CouchCoder/Config/.env
SSH_PRIVATE_KEY_PATH=/Users/you/.ssh/id_ed25519
```

If you prefer to inline the key, wrap it in quotes inside `.env` and replace line breaks with `\n` so the parser can restore them at runtime.

**Important:** Make sure the public key is in `~/.ssh/authorized_keys` on your Mac:
```bash
# Check if it's already there
grep "$(cat ~/.ssh/id_ed25519.pub)" ~/.ssh/authorized_keys

# If not found, add it:
cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
```

## Mac Setup Checklist

1. **Enable SSH (Remote Login)**
   - System Settings → General → Sharing → toggle **Remote Login**.
   - Make sure your public key is in `~/.ssh/authorized_keys` (see "Getting an SSH Private Key" above).

2. **Wireless Debugging**
   - Connect your iPhone via USB once, open Xcode → Window → Devices & Simulators.
   - Select your iPhone, check **Connect via network**.

3. **Install command-line helpers**
   - Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the “New Project” flow can run remotely:
     ```bash
     brew install xcodegen
     ```
   - Ensure `/opt/homebrew/bin` (Apple Silicon) or `/usr/local/bin` (Intel) is in your shell `PATH`; CouchCoder adds these paths automatically, but custom setups might need tweaks.

4. **Same Wi‑Fi, Same LAN**
   - Both devices must be on the same network. Bonjour hostnames like `your-mac.local` work best.


## Running the App

1. Open `CouchCoder.xcodeproj` in Xcode 26.0+.
2. Update `CouchCoder/Config/.env` (or add `.env.local`) with your SSH + device details.
3. Select your personal device target (iOS 26 min deployment).
4. Build & run. You should see your projects, tap one to open the chat-style shell, and vibe away.

## Notes & Next Ideas

- This repo vendors SwiftSH because the upstream dependency graph needs tweaks for modern SwiftPM. Keep it synced manually if you pull upstream changes.
- Hidden projects persist in `UserDefaults`. Use the eye toolbar button to temporarily show them.
- No analytics, no logging—just a cozy remote terminal.

Happy couch coding! 🛋️⌨️
