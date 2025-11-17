//
//  TerminalSessionViewModel.swift
//  CouchCoder
//
//  Created by ChatGPT on 11/16/25.
//

import Foundation
import UIKit
import Combine

@MainActor
final class TerminalSessionViewModel: ObservableObject {
    @Published var agent: Agent = .codex // Default to Codex
    @Published private(set) var state: SSHConnection.State = .idle
    @Published private(set) var buildErrorText: String? = nil
    @Published private(set) var hasBuildError: Bool = false

    let project: Project
    let terminalBridge: TerminalBridge

    private let connection: SSHConnection
    private var cancellables = Set<AnyCancellable>()
    private var buildErrorDetectionTask: Task<Void, Never>?
    
    #if DEBUG
    private func log(_ message: String) {
        print("[Session:\(project.name)] \(message)")
    }
    #else
    private func log(_ message: String) {}
    #endif

    init(project: Project) {
        self.project = project
        self.connection = SSHManager.shared.session(for: project)
        self.terminalBridge = TerminalBridge(ssh: connection)
        
        // Set initial agent
        connection.setAgent(agent)

        connection.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in
                guard let self = self else { return }
                self.state = newState
            }
            .store(in: &cancellables)
        
        // Monitor terminal output for build failures
        connection.terminalOutputPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] data in
                self?.checkForBuildErrors(in: data)
            }
            .store(in: &cancellables)
    }

    func start() {
        Task {
            await connection.connectIfNeeded()
        }
    }


    func paste() {
        // Get clipboard content and send to terminal
        #if os(iOS)
        if let clipboardString = UIPasteboard.general.string {
            terminalBridge.sendText(clipboardString)
            log("Pasted: \(clipboardString)")
        }
        #endif
    }

    func sendRaw(_ sequence: String) {
        log("Sending raw sequence: \(sequence.replacingOccurrences(of: "\n", with: "\\n"))")
        Task {
            await connection.send(raw: sequence)
        }
    }
    
    func buildAndInstall() {
        let deviceUDID = AppConfig.deviceUDID
        let keychainPassword = Self.escapeForSingleQuotes(AppConfig.keychainPassword)

        let detectCommand = """
        cat > /tmp/build_couchcoder.sh << 'BUILDSCRIPT'
        security unlock-keychain -p '\(keychainPassword)' ~/Library/Keychains/login.keychain-db 2>/dev/null || true
        setopt nonomatch 2>/dev/null || set +f

        # Helper: dump build settings and pull out paths / bundle id / identity
        resolve_build_info_workspace() {
            local WORKSPACE="$1"
            local SCHEME="$2"
            APP_INFO=$(/usr/bin/xcrun xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration Debug -showBuildSettings -json 2>/dev/null | /usr/bin/python3 - << 'PY'
        import json, sys
        data = json.load(sys.stdin)[0]["buildSettings"]
        print(data.get("TARGET_BUILD_DIR",""))
        print(data.get("WRAPPER_NAME",""))
        print(data.get("EXECUTABLE_NAME",""))
        print(data.get("PRODUCT_BUNDLE_IDENTIFIER",""))
        print(data.get("CODE_SIGN_IDENTITY",""))
        PY
        )
                IFS=$'\n' read -r TARGET_BUILD_DIR WRAPPER_NAME EXECUTABLE_NAME BUNDLE_ID CODE_SIGN_IDENTITY << EOF
        $APP_INFO
        EOF
                APP_PATH="$TARGET_BUILD_DIR/$WRAPPER_NAME"
            }

            resolve_build_info_project() {
                local PROJECT="$1"
                local SCHEME="$2"
                APP_INFO=$(/usr/bin/xcrun xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug -showBuildSettings -json 2>/dev/null | /usr/bin/python3 - << 'PY'
        import json, sys
        data = json.load(sys.stdin)[0]["buildSettings"]
        print(data.get("TARGET_BUILD_DIR",""))
        print(data.get("WRAPPER_NAME",""))
        print(data.get("EXECUTABLE_NAME",""))
        print(data.get("PRODUCT_BUNDLE_IDENTIFIER",""))
        print(data.get("CODE_SIGN_IDENTITY",""))
        PY
        )
                IFS=$'\n' read -r TARGET_BUILD_DIR WRAPPER_NAME EXECUTABLE_NAME BUNDLE_ID CODE_SIGN_IDENTITY << EOF
        $APP_INFO
        EOF
            APP_PATH="$TARGET_BUILD_DIR/$WRAPPER_NAME"
        }

        if ls -d *.xcworkspace 1>/dev/null 2>&1; then
            WORKSPACE=$(ls -1d *.xcworkspace | head -1)
            echo "Found workspace: $WORKSPACE"
            SCHEME=$(/usr/bin/xcrun xcodebuild -list -json -workspace "$WORKSPACE" 2>/dev/null | /usr/bin/python3 -c "import json,sys; data=json.load(sys.stdin); target=data.get('workspace') or {}; schemes=target.get('schemes') or []; print(schemes[0] if schemes else '')" 2>/dev/null | /usr/bin/tr -d '\\r' || true)
            echo "Detected scheme: '$SCHEME'"
            if [ -n "$SCHEME" ]; then
                resolve_build_info_workspace "$WORKSPACE" "$SCHEME"
                echo "Target dir: $TARGET_BUILD_DIR"
                echo "App path:   $APP_PATH"
                echo "Bundle id:  $BUNDLE_ID"

                echo "Building scheme: $SCHEME for device \(deviceUDID)"
                echo "Checking code signing setup..."
                /usr/bin/xcrun security find-identity -v -p codesigning 2>&1 | head -3 || echo "Warning: No code signing identity found"
                echo ""
                echo "Attempting build..."

                if /usr/bin/xcrun xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration Debug -destination "platform=iOS,id=\(deviceUDID)" -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=32LGBT83RQ build 2>&1 | tee /tmp/xcodebuild.log; then
                    if grep -q "BUILD SUCCEEDED" /tmp/xcodebuild.log 2>/dev/null; then
                        echo ""
                        echo "[SUCCESS] Build succeeded! Finding app bundle..."
                        echo "Looking for WRAPPER_NAME: $WRAPPER_NAME"
                        cd ~/Library/Developer/Xcode/DerivedData
                        # Try multiple search patterns
                        APP_PATH=$(find . -path "*$SCHEME-*/Build/Products/*-iphoneos/$WRAPPER_NAME" ! -path "*/Index.noindex/*" -print -quit 2>/dev/null)
                        if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
                            # Fallback: search for any .app in the scheme's DerivedData folder
                            APP_PATH=$(find . -path "*$SCHEME-*/Build/Products/*-iphoneos/*.app" ! -path "*/Index.noindex/*" -type d -print -quit 2>/dev/null)
                        fi
                        if [ -n "$APP_PATH" ] && [ -d "$APP_PATH" ]; then
                            APP_PATH=$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")
                            echo "Using app at: $APP_PATH"
                            echo ""
                            echo "[INSTALL] Installing app..."
                            if /usr/bin/xcrun devicectl device install app --device \(deviceUDID) "$APP_PATH" 2>&1; then
                                echo ""
                                echo "[LAUNCH] Launching app..."
                                /usr/bin/xcrun devicectl device process launch --device \(deviceUDID) "$BUNDLE_ID" 2>&1 || echo "Launch command completed"
                            else
                                echo "Install failed"
                            fi
                        else
                            echo "Could not find app bundle."
                            echo "Searched for: *$SCHEME-*/Build/Products/*-iphoneos/$WRAPPER_NAME"
                            echo "Also tried: *$SCHEME-*/Build/Products/*-iphoneos/*.app"
                            echo "Listing available DerivedData folders:"
                            ls -1d *$SCHEME-* 2>/dev/null | head -3 || echo "None found"
                        fi
                    fi
                else
                    echo ""
                    echo "Build failed. Checking if it's the debug dylib signing issue..."
                    if grep -q "errSecInternalComponent.*debug.dylib" /tmp/xcodebuild.log 2>/dev/null; then
                        echo "Detected debug dylib signing issue. Applying workaround..."
                        if [ -n "$APP_PATH" ] && [ -d "$APP_PATH" ]; then
                            DEBUG_DYLIB="$APP_PATH/$EXECUTABLE_NAME.debug.dylib"
                            if [ -f "$DEBUG_DYLIB" ]; then
                                echo "Removing debug dylib: $DEBUG_DYLIB"
                                rm -f "$DEBUG_DYLIB"
                                echo "Re-signing app binary..."
                                ENTITLEMENTS=$(find "$TARGET_BUILD_DIR" -name "*.app.xcent" -path "*/Debug-iphoneos/*" 2>/dev/null | head -1)
                                if [ -n "$ENTITLEMENTS" ] && [ -n "$CODE_SIGN_IDENTITY" ]; then
                                    /usr/bin/codesign --force --sign "$CODE_SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_PATH/$EXECUTABLE_NAME" 2>&1 || echo "Re-signing failed, but continuing..."
                                fi
                                echo "Retrying install..."
                                cd ~/Library/Developer/Xcode/DerivedData
                                APP_PATH=$(find . -path "*$SCHEME-*/Build/Products/*-iphoneos/$WRAPPER_NAME" ! -path "*/Index.noindex/*" -print -quit 2>/dev/null)
                                if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
                                    APP_PATH=$(find . -path "*$SCHEME-*/Build/Products/*-iphoneos/*.app" ! -path "*/Index.noindex/*" -type d -print -quit 2>/dev/null)
                                fi
                                if [ -n "$APP_PATH" ] && [ -d "$APP_PATH" ]; then
                                    APP_PATH=$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")
                                    echo "Using app at: $APP_PATH"
                                    if /usr/bin/xcrun devicectl device install app --device \(deviceUDID) "$APP_PATH" 2>&1; then
                                        echo ""
                                        echo "[LAUNCH] Launching app..."
                                        /usr/bin/xcrun devicectl device process launch --device \(deviceUDID) "$BUNDLE_ID" 2>&1 || echo "Launch command completed"
                                    else
                                        echo "Install failed"
                                    fi
                                else
                                    echo "Could not find app bundle after re-signing"
                                fi
                            else
                                echo "Debug dylib not found at: $DEBUG_DYLIB"
                                grep -A 5 -B 5 "CodeSign\\|codesign\\|error:" /tmp/xcodebuild.log | tail -30 || cat /tmp/xcodebuild.log | tail -50
                            fi
                        else
                            echo "App bundle not found at: $APP_PATH"
                            grep -A 5 -B 5 "CodeSign\\|codesign\\|error:" /tmp/xcodebuild.log | tail -30 || cat /tmp/xcodebuild.log | tail -50
                        fi
                    else
                        echo ""
                        echo "Build failed. Showing codesign errors from log:"
                        grep -A 5 -B 5 "CodeSign\\|codesign\\|error:" /tmp/xcodebuild.log | tail -30 || cat /tmp/xcodebuild.log | tail -50
                    fi
                fi
            else
                echo "No schemes found. Listing all:"
                /usr/bin/xcrun xcodebuild -list -workspace "$WORKSPACE" 2>/dev/null
            fi

        elif ls -d *.xcodeproj 1>/dev/null 2>&1; then
            PROJECT=$(ls -1d *.xcodeproj | head -1)
            echo "Found project: $PROJECT"
            SCHEME=$(/usr/bin/xcrun xcodebuild -list -json -project "$PROJECT" 2>/dev/null | /usr/bin/python3 -c "import json,sys; data=json.load(sys.stdin); target=data.get('project') or {}; schemes=target.get('schemes') or []; print(schemes[0] if schemes else '')" 2>/dev/null | /usr/bin/tr -d '\\r' || true)
            echo "Detected scheme: '$SCHEME'"
            if [ -n "$SCHEME" ]; then
                resolve_build_info_project "$PROJECT" "$SCHEME"
                echo "Target dir: $TARGET_BUILD_DIR"
                echo "App path:   $APP_PATH"
                echo "Bundle id:  $BUNDLE_ID"

                echo "Building scheme: $SCHEME for device \(deviceUDID)"
                echo "Checking code signing setup..."
                /usr/bin/xcrun security find-identity -v -p codesigning 2>&1 | head -3 || echo "Warning: No code signing identity found"
                echo ""
                echo "Attempting build..."

                if /usr/bin/xcrun xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug -destination "platform=iOS,id=\(deviceUDID)" -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=32LGBT83RQ build 2>&1 | tee /tmp/xcodebuild.log; then
                    if grep -q "BUILD SUCCEEDED" /tmp/xcodebuild.log 2>/dev/null; then
                        echo ""
                        echo "[SUCCESS] Build succeeded! Finding app bundle..."
                        echo "Looking for WRAPPER_NAME: $WRAPPER_NAME"
                        cd ~/Library/Developer/Xcode/DerivedData
                        # Try multiple search patterns
                        APP_PATH=$(find . -path "*$SCHEME-*/Build/Products/*-iphoneos/$WRAPPER_NAME" ! -path "*/Index.noindex/*" -print -quit 2>/dev/null)
                        if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
                            # Fallback: search for any .app in the scheme's DerivedData folder
                            APP_PATH=$(find . -path "*$SCHEME-*/Build/Products/*-iphoneos/*.app" ! -path "*/Index.noindex/*" -type d -print -quit 2>/dev/null)
                        fi
                        if [ -n "$APP_PATH" ] && [ -d "$APP_PATH" ]; then
                            APP_PATH=$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")
                            echo "Using app at: $APP_PATH"
                            echo ""
                            echo "[INSTALL] Installing app..."
                            if /usr/bin/xcrun devicectl device install app --device \(deviceUDID) "$APP_PATH" 2>&1; then
                                echo ""
                                echo "[LAUNCH] Launching app..."
                                /usr/bin/xcrun devicectl device process launch --device \(deviceUDID) "$BUNDLE_ID" 2>&1 || echo "Launch command completed"
                            else
                                echo "Install failed"
                            fi
                        else
                            echo "Could not find app bundle."
                            echo "Searched for: *$SCHEME-*/Build/Products/*-iphoneos/$WRAPPER_NAME"
                            echo "Also tried: *$SCHEME-*/Build/Products/*-iphoneos/*.app"
                            echo "Listing available DerivedData folders:"
                            ls -1d *$SCHEME-* 2>/dev/null | head -3 || echo "None found"
                        fi
                    fi
                else
                    echo ""
                    echo "Build failed. Checking if it's the debug dylib signing issue..."
                    if grep -q "errSecInternalComponent.*debug.dylib" /tmp/xcodebuild.log 2>/dev/null; then
                        echo "Detected debug dylib signing issue. Applying workaround..."
                        if [ -n "$APP_PATH" ] && [ -d "$APP_PATH" ]; then
                            DEBUG_DYLIB="$APP_PATH/$EXECUTABLE_NAME.debug.dylib"
                            if [ -f "$DEBUG_DYLIB" ]; then
                                echo "Removing debug dylib: $DEBUG_DYLIB"
                                rm -f "$DEBUG_DYLIB"
                                echo "Re-signing app binary..."
                                ENTITLEMENTS=$(find "$TARGET_BUILD_DIR" -name "*.app.xcent" -path "*/Debug-iphoneos/*" 2>/dev/null | head -1)
                                if [ -n "$ENTITLEMENTS" ] && [ -n "$CODE_SIGN_IDENTITY" ]; then
                                    /usr/bin/codesign --force --sign "$CODE_SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_PATH/$EXECUTABLE_NAME" 2>&1 || echo "Re-signing failed, but continuing..."
                                fi
                                echo "Retrying install..."
                                cd ~/Library/Developer/Xcode/DerivedData
                                APP_PATH=$(find . -path "*$SCHEME-*/Build/Products/*-iphoneos/$WRAPPER_NAME" ! -path "*/Index.noindex/*" -print -quit 2>/dev/null)
                                if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
                                    APP_PATH=$(find . -path "*$SCHEME-*/Build/Products/*-iphoneos/*.app" ! -path "*/Index.noindex/*" -type d -print -quit 2>/dev/null)
                                fi
                                if [ -n "$APP_PATH" ] && [ -d "$APP_PATH" ]; then
                                    APP_PATH=$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")
                                    echo "Using app at: $APP_PATH"
                                    if /usr/bin/xcrun devicectl device install app --device \(deviceUDID) "$APP_PATH" 2>&1; then
                                        echo ""
                                        echo "[LAUNCH] Launching app..."
                                        /usr/bin/xcrun devicectl device process launch --device \(deviceUDID) "$BUNDLE_ID" 2>&1 || echo "Launch command completed"
                                    else
                                        echo "Install failed"
                                    fi
                                else
                                    echo "Could not find app bundle after re-signing"
                                fi
                            else
                                echo "Debug dylib not found at: $DEBUG_DYLIB"
                                grep -A 5 -B 5 "CodeSign\\|codesign\\|error:" /tmp/xcodebuild.log | tail -30 || cat /tmp/xcodebuild.log | tail -50
                            fi
                        else
                            echo "App bundle not found at: $APP_PATH"
                            grep -A 5 -B 5 "CodeSign\\|codesign\\|error:" /tmp/xcodebuild.log | tail -30 || cat /tmp/xcodebuild.log | tail -50
                        fi
                    else
                        echo ""
                        echo "Build failed. Showing codesign errors from log:"
                        grep -A 5 -B 5 "CodeSign\\|codesign\\|error:" /tmp/xcodebuild.log | tail -30 || cat /tmp/xcodebuild.log | tail -50
                    fi
                fi
            else
                echo "No schemes found. Listing all:"
                /usr/bin/xcrun xcodebuild -list -project "$PROJECT" 2>/dev/null
            fi
        else
            echo "No Xcode project found in current directory"
        fi
        BUILDSCRIPT
        chmod +x /tmp/build_couchcoder.sh
        /tmp/build_couchcoder.sh
        """

        log("Building project in current directory...")
        terminalBridge.sendPrompt(detectCommand)
    }

    
    func sendGitCommand() {
        let command = AppConfig.gitOneLiner
        log("Running git command: \(command)")
        terminalBridge.sendPrompt(command)
    }
    
    func launchCodex() {
        Task {
            log("📤 Launching Codex in terminal...")
            await connection.send(line: "codex")
            log("✅ Codex launched!")
        }
    }
    
    // MARK: - Build Error Detection
    
    private func checkForBuildErrors(in data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        
        // Check for build failure indicators
        let buildFailedPatterns = [
            "BUILD FAILED",
            "error:",
            "** BUILD FAILED **",
            "The following build commands failed:"
        ]
        
        let hasBuildFailure = buildFailedPatterns.contains { pattern in
            text.range(of: pattern, options: .caseInsensitive) != nil
        }
        
        if hasBuildFailure {
            hasBuildError = true
            
            // Accumulate error text from terminal output
            if buildErrorText == nil {
                buildErrorText = ""
            }
            
            // Append error-related lines
            let lines = text.components(separatedBy: .newlines)
            let errorLines = lines.filter { line in
                buildFailedPatterns.contains { pattern in
                    line.range(of: pattern, options: .caseInsensitive) != nil
                }
            }
            
            if !errorLines.isEmpty {
                buildErrorText = (buildErrorText ?? "") + errorLines.joined(separator: "\n") + "\n"
            }
            
            // Start monitoring for more error text
            buildErrorDetectionTask?.cancel()
            buildErrorDetectionTask = Task { [weak self] in
                // Wait a moment for errors to accumulate
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                guard !Task.isCancelled else { return }
                await self?.extractBuildErrors()
            }
        }
        
        // Check for build success to clear errors
        if text.contains("BUILD SUCCEEDED") {
            hasBuildError = false
            buildErrorText = nil
            buildErrorDetectionTask?.cancel()
        }
    }
    
    private func extractBuildErrors() async {
        // Read from /tmp/xcodebuild.log if available
        let logPath = "/tmp/xcodebuild.log"
        
        // Extract error lines from the log file
        let extractErrorsCommand = """
        if [ -f \(logPath) ]; then
            # Extract error lines and build failure messages
            grep -E "(error:|warning:|BUILD FAILED|The following build commands failed)" \(logPath) | tail -50
            echo "---"
            # Also get the summary at the end
            tail -20 \(logPath) | grep -E "(error:|BUILD FAILED|failed)" || tail -20 \(logPath)
        else
            echo "Log file not found at \(logPath)"
        fi
        """
        
        hasBuildError = true
        
        // Send command to extract errors
        await connection.send(line: extractErrorsCommand)
        
        // The error text will be captured in checkForBuildErrors as terminal output
    }
    
    func copyBuildErrors() {
        Task {
            do {
                // Read the log file and extract errors
                let extractCommand = """
                if [ -f /tmp/xcodebuild.log ]; then
                    echo "=== Build Errors ==="
                    grep -E "(error:|warning:|BUILD FAILED|The following build commands failed)" /tmp/xcodebuild.log | tail -100
                    echo ""
                    echo "=== Build Summary ==="
                    tail -30 /tmp/xcodebuild.log
                else
                    echo "Log file not found at /tmp/xcodebuild.log"
                fi
                """
                
                let errorText = try await connection.executeCommand(extractCommand)
                
                // Copy to iOS clipboard
                await MainActor.run {
                    UIPasteboard.general.string = errorText
                    log("✅ Build errors copied to clipboard (\(errorText.count) characters)")
                }
            } catch {
                log("❌ Failed to copy build errors: \(error.localizedDescription)")
                // Fallback: copy a message
                UIPasteboard.general.string = "Failed to read build errors. Check terminal output or /tmp/xcodebuild.log"
            }
        }
    }
}

private extension TerminalSessionViewModel {
    static func escapeForSingleQuotes(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\"'\"'")
    }
}
