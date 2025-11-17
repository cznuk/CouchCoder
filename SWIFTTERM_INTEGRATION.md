# SwiftTerm Integration Summary

## What Was Implemented

This integration adds a proper terminal emulator (SwiftTerm) to display Codex TUI without escape code garbage, while keeping the layered chat + terminal experience.

## Architecture Changes

### 1. New Models

**`TranscriptItem.swift`** - New model for Codex chat display:
- `.user(id, text)` - Blue user message bubbles
- `.frame(id, image)` - Terminal snapshot cards

### 2. Terminal Bridge

**`TerminalBridge.swift`** - Connects SwiftTerm to SSH:
- Implements `TerminalViewDelegate` protocol
- Forwards SSH output to terminal emulator
- Sends user input from terminal to SSH
- Provides `sendPrompt(_)` to type commands + Enter
- Provides `snapshot()` to capture terminal as UIImage

### 3. Terminal View Wrapper

**`TerminalPaneView.swift`** - SwiftUI wrapper for SwiftTerm:
- Uses `UIViewRepresentable` to embed TerminalView
- Configures appearance (colors, font)
- Connects to TerminalBridge

### 4. SSH Manager Updates

**`SSHManager.swift`** - Enhanced output routing:
- Added `terminalOutputPublisher` for raw terminal data
- Added `currentAgent` tracking
- **Key change**: When agent is `.codex`, skips text output to `outputSubject`
  - Codex TUI escape codes go only to terminal emulator
  - Other agents still get processed text in message bubbles
- Added `setAgent(_)` to configure output routing
- Added `writeRaw(_)` for terminal input
- Added `resize(cols:rows:)` for PTY resizing (placeholder)

### 5. View Model Updates

**`TerminalSessionViewModel.swift`**:
- Added `items: [TranscriptItem]` for Codex transcript
- Added `terminalBridge: TerminalBridge` instance
- Modified `sendCurrentCommand()`:
  - **For Codex**: Adds user bubble → sends to terminal → snapshots after 1s delay
  - **For other agents**: Uses original message-based flow
- Sets agent on connection during init and agent changes

### 6. View Updates

**`TerminalChatView.swift`**:
- Conditional layout based on agent:
  - **Codex**: Shows `transcriptList` (user bubbles + frame cards) + bottom terminal pane
  - **Other agents**: Shows original `messagesList` (dual bubbles)
- Added `transcriptList` view for Codex items
- Added `messagesList` view for legacy messages
- Terminal pane shows at bottom with 240pt min height when Codex is active
- Added `UserBubble` component for blue chat bubbles
- Added `TerminalFrameCard` component for terminal snapshots

## User Experience Flow (Codex Mode)

1. User types message and sends
2. Blue user bubble appears in transcript
3. Message is sent to Codex TUI in the live terminal (bottom pane)
4. After 1 second, a snapshot of the terminal is captured
5. Terminal snapshot card appears in transcript below the user bubble
6. Live terminal at bottom continues to show Codex TUI in real-time

## Benefits

✅ **No more escape code garbage** - Codex TUI is properly rendered in terminal emulator
✅ **Full TUI experience** - All Codex features work (colors, cursor movement, interactive elements)
✅ **Chat-style history** - Blue bubbles show what you asked, frame cards show responses
✅ **Live terminal** - Bottom pane shows current Codex state for interaction
✅ **Backward compatible** - Other agents (cursor-agent) still use original text bubble flow

## Technical Notes

- SwiftTerm handles all escape sequences natively
- SSH output is bifurcated:
  - Raw bytes → `terminalOutputPublisher` → SwiftTerm
  - Processed text → `outputPublisher` → message bubbles (only for non-Codex agents)
- Terminal snapshots are captured as UIImage using `UIGraphicsImageRenderer`
- The 1-second delay for snapshots can be tuned (currently 1000ms)
- TerminalView is configured with xterm-256color compatibility

## Future Enhancements

- Adjustable snapshot delay based on response time
- Ability to tap frame cards to expand/zoom
- Option to toggle terminal pane visibility
- PTY resize support when SwiftSH exposes it
- Terminal session persistence across app restarts


