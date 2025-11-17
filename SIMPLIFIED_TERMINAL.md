# Simplified Terminal Experience

## What Changed

Simplified the app to provide a direct terminal experience with Codex running immediately when you open a project. No more dual bubble views, transcripts, or agent switching - just a full-screen terminal with Codex TUI.

## Key Simplifications

### 1. **Direct Terminal View**
- Removed dual display logic (bubbles vs terminal)
- Full-screen SwiftTerm terminal pane
- All Codex TUI output renders properly with escape codes

### 2. **Automatic Codex Launch**
- Opens Codex immediately when project is selected
- No manual launch step needed
- Waits 2 seconds for shell initialization then starts Codex

### 3. **Simplified Input**
- Type directly inside SwiftTerm (no separate text field)
- Clipboard actions still flow through `terminalBridge.sendPrompt()`
- No transcript items or message bubbles

### 4. **Enhanced Shortcuts**
- **Paste** - Paste clipboard content into terminal
- **Ctrl+C** - Send interrupt signal
- Built-in SwiftTerm accessory provides Esc/Ctrl/arrow keys

## Removed Features

- ❌ Agent picker (always uses Codex now)
- ❌ Build & Git toolbar buttons
- ❌ Message bubbles (user and terminal)
- ❌ Transcript items with terminal snapshots
- ❌ Message history tracking
- ❌ Output text processing for display

## Architecture

### View Model (`TerminalSessionViewModel`)

**Properties:**
- `agent` - Always `.codex`
- `state` - SSH connection state
- `terminalBridge` - Bridge to SwiftTerm

**Methods:**
- `start()` - Initialize SSH connection
- `paste()` - Paste clipboard to terminal
- `sendRaw(_)` - Send raw escape sequences

**Flow:**
1. Connection becomes ready
2. Wait 2 seconds for shell init
3. Launch Codex with `codex` command
4. User types and sends messages directly to terminal
5. SwiftTerm renders all TUI output

### View (`TerminalChatView`)

**Layout:**
```
┌─────────────────────────┐
│    Connection Badge     │  <- Toolbar
├─────────────────────────┤
│                         │
│   TerminalPaneView      │  <- Full screen
│   (SwiftTerm)           │
│                         │
├─────────────────────────┤
│ Paste   Ctrl+C          │  <- Shortcut bar
└─────────────────────────┘
```

### Terminal Bridge (`TerminalBridge`)

- Connects SwiftTerm to SSH
- Forwards raw SSH output to terminal emulator
- Sends user input from terminal to SSH
- `sendPrompt(_)` types text and presses Enter

## User Flow

1. **Open Project** → Immediately launches Codex in terminal
2. **Type Message** → Press send or Enter
3. **Terminal Receives** → Codex processes and responds in TUI
4. **Use Shortcuts** → Tab, Paste, Ctrl+C, Enter, Arrows for interaction
5. **See Real-Time** → All Codex TUI features work (colors, menus, status)

## Technical Benefits

✅ **Simpler codebase** - Removed transcript, message bubbles, agent switching
✅ **Better performance** - No text processing, ANSI stripping, or message appending
✅ **Full TUI support** - All Codex features work natively in terminal
✅ **Direct interaction** - Type and see results immediately
✅ **Clipboard integration** - Easy paste button for long prompts

## Files Modified

- `TerminalSessionViewModel.swift` - Removed message/transcript logic, simplified to direct terminal sends
- `TerminalChatView.swift` - Removed bubbles/transcript views, shows only terminal pane
- `TerminalPaneView.swift` - Customizes SwiftTerm accessory to swap `~`/`|` with Paste + Ctrl+C
- Shortcut bar now only exposes Paste + Ctrl+C

## Files Unchanged

- `TerminalBridge.swift` - Bridge logic remains the same
- `SSHManager.swift` - SSH connection logic preserved
- `TranscriptItem.swift` - Not used but kept for future use
