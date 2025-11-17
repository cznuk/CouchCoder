//
//  ContentView.swift
//  CouchCoder
//
//  Created by Chase Kunz on 11/16/25.
//

import SwiftUI

private enum ProjectListPreferenceKey {
    static let showHiddenProjects = "com.couchcoder.app.showHiddenProjects"
}

private extension ProjectAccentColor {
    var color: Color {
        switch self {
        case .sky:
            return Color.blue
        case .grape:
            return Color.purple
        case .mango:
            return Color.orange
        case .mint:
            return Color.green
        case .rose:
            return Color.pink
        case .twilight:
            return Color.teal
        }
    }
}

struct ProjectListView: View {
    @ObservedObject private var manager = ProjectManager.shared
    @AppStorage(ProjectListPreferenceKey.showHiddenProjects) private var showHiddenProjects = false
    @State private var searchText = ""
    @State private var navigationPath = NavigationPath()
    @State private var isPresentingNewProjectSheet = false
    @State private var newProjectForm = NewProjectForm()
    @State private var isCreatingProject = false
    @State private var creationError: String?

    private let pinnedGridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    private var visibleProjects: [Project] {
        manager.visibleProjects
            .filter { matchesSearch(project: $0) }
    }

    private var pinnedProjects: [Project] {
        manager.pinnedProjects
            .filter { matchesSearch(project: $0) }
    }

    private var hiddenProjects: [Project] {
        manager.hiddenProjects
            .filter { matchesSearch(project: $0) }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                if !pinnedProjects.isEmpty {
                    Section {
                        pinnedGrid
                    } header: {
                        Label("Pinned", systemImage: "pin.fill")
                    }
                }

                if visibleProjects.isEmpty && !manager.isLoading {
                    emptyState
                } else {
                    Section("Projects") {
                        ForEach(visibleProjects) { project in
                            ProjectRowView(
                                project: project,
                                onLongPress: { manager.advanceAccentColor(for: project) }
                            )
                            .onTapGesture {
                                navigationPath.append(project)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    manager.setPinned(!project.isPinned, for: project)
                                } label: {
                                    Label(project.isPinned ? "Unpin" : "Pin",
                                          systemImage: project.isPinned ? "pin.slash" : "pin.fill")
                                }
                                .tint(project.isPinned ? .gray : .yellow)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    manager.setHidden(true, for: project)
                                } label: {
                                    Label("Hide", systemImage: "eye.slash")
                                }
                            }
                        }
                    }
                }

                if !hiddenProjects.isEmpty {
                    Section("Hidden") {
                        if showHiddenProjects {
                            ForEach(hiddenProjects) { project in
                                ProjectRowView(
                                    project: project,
                                    isHidden: true,
                                    onLongPress: { manager.advanceAccentColor(for: project) }
                                )
                                .onTapGesture {
                                    navigationPath.append(project)
                                }
                                .swipeActions {
                                    Button {
                                        manager.setHidden(false, for: project)
                                    } label: {
                                        Label("Unhide", systemImage: "eye")
                                    }
                                    .tint(.blue)
                                }
                            }
                        } else {
                            HStack {
                                Label("Hidden projects", systemImage: "eye.slash")
                                Spacer()
                                Text("Tap the eye to view")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .navigationDestination(for: Project.self) { project in
                TerminalChatView(project: project)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Coder")
            .toolbarTitleDisplayMode(.inlineLarge)
            .overlay(alignment: .center) {
                if manager.isLoading {
                    ProgressView("Looking around…")
                        .padding()
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .overlay(alignment: .bottom) {
                if let error = manager.lastError {
                    errorBanner(error)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showHiddenProjects.toggle()
                    } label: {
                        Image(systemName: showHiddenProjects ? "eye.slash.fill" : "eye.fill")
                    }
                    Button {
                        Task { await manager.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                }
            }
            .refreshable {
                await manager.refresh()
            }
            .task {
                await manager.refresh()
            }
            .onChange(of: hiddenProjects.count) { oldValue, newValue in
                if newValue > 0 && oldValue == 0 {
                    showHiddenProjects = true
                } else if newValue == 0 {
                    showHiddenProjects = false
                }
            }
            .safeAreaInset(edge: .top) {
                ProjectSearchHeader(searchText: $searchText) {
                    isPresentingNewProjectSheet = true
                }
                .background(.bar)
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
            }
            .sheet(isPresented: $isPresentingNewProjectSheet) {
                NavigationStack {
                    NewProjectSheet(
                        form: $newProjectForm,
                        isCreating: isCreatingProject,
                        onCancel: { dismissNewProjectSheet() },
                        onCreate: { createProject() }
                    )
                }
                .presentationDetents([.medium, .large])
            }
            .alert(
                "Unable to Create Project",
                isPresented: Binding(
                    get: { creationError != nil },
                    set: { if !$0 { creationError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    creationError = nil
                }
            } message: {
                Text(creationError ?? "Something went wrong.")
            }
        }
    }

    private func matchesSearch(project: Project) -> Bool {
        guard !searchText.isEmpty else { return true }
        return project.name.localizedCaseInsensitiveContains(searchText)
    }

    private func dismissNewProjectSheet() {
        guard !isCreatingProject else { return }
        isPresentingNewProjectSheet = false
        newProjectForm = NewProjectForm()
    }

    private func createProject() {
        guard newProjectForm.isValid else { return }
        isCreatingProject = true
        Task {
            do {
                try await manager.createProject(request: newProjectForm.buildRequest())
                await MainActor.run {
                    isCreatingProject = false
                    isPresentingNewProjectSheet = false
                    newProjectForm = NewProjectForm()
                }
            } catch {
                await MainActor.run {
                    creationError = error.localizedDescription
                    isCreatingProject = false
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No projects yet")
                .font(.headline)
            Text("Pull to refresh once your Mac is awake on Wi-Fi.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 60)
        .listRowBackground(Color.clear)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
            Text(message)
                .lineLimit(2)
        }
        .font(.footnote)
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: Capsule())
        .padding()
    }

    private var pinnedGrid: some View {
        LazyVGrid(columns: pinnedGridColumns, spacing: 16) {
            ForEach(pinnedProjects) { project in
                PinnedProjectTile(
                    project: project,
                    onLongPress: { manager.advanceAccentColor(for: project) }
                )
                .onTapGesture {
                    navigationPath.append(project)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

private struct ProjectRowView: View {
    let project: Project
    var isHidden: Bool = false
    var onLongPress: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(project.accentColor.color.opacity(isHidden ? 0.15 : 0.3))
                    .frame(width: 44, height: 44)
                Text(project.name.prefix(2).uppercased())
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(project.name)
                        .font(.headline)
                        .foregroundStyle(isHidden ? .secondary : .primary)
                    if project.isPinned && !isHidden {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                    Spacer()
                    if let date = project.lastActivity {
                        Text(date.formatted(.dateTime.hour().minute()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(project.lastMessagePreview ?? "Tap to start a couch code session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    onLongPress?()
                }
        )
    }
}

private struct PinnedProjectTile: View {
    let project: Project
    var onLongPress: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(project.accentColor.color.opacity(0.2))
                .overlay(
                    Text(project.name.prefix(2).uppercased())
                        .font(.headline)
                        .foregroundStyle(.primary)
                )
                .frame(width: 64, height: 64)
            Text(project.name)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    onLongPress?()
                }
        )
    }
}

private struct ProjectSearchHeader: View {
    @Binding var searchText: String
    var onNewProject: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search projects", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            .layoutPriority(1)

            Button(action: onNewProject) {
                Label("New Project", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

private struct NewProjectSheet: View {
    @Binding var form: NewProjectForm
    var isCreating: Bool
    var onCancel: () -> Void
    var onCreate: () -> Void
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case bundlePrefix
        case deployment
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Project name", text: $form.projectName)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .name)
                if !form.folderName.isEmpty {
                    LabeledContent("Folder") {
                        Text(form.folderName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("The folder will be created inside \(AppConfig.projectsBasePath).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Identifiers") {
                TextField("Bundle ID prefix", text: $form.bundleIdPrefix)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .bundlePrefix)
                if !form.bundleIdentifier.isEmpty {
                    LabeledContent("Bundle ID") {
                        Text(form.bundleIdentifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Deployment Target") {
                TextField("iOS Deployment Target", text: $form.deploymentTarget)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .deployment)
            }

            if let validation = form.validationMessage {
                Section {
                    Text(validation)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("New Project")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .disabled(isCreating)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    onCreate()
                } label: {
                    if isCreating {
                        ProgressView()
                    } else {
                        Text("Create")
                            .bold()
                    }
                }
                .disabled(!form.isValid || isCreating)
            }
        }
        .onSubmit {
            if focusedField == .name {
                focusedField = .bundlePrefix
            } else {
                onCreate()
            }
        }
    }
}

private struct NewProjectForm {
    var projectName: String = ""
    var bundleIdPrefix: String = AppConfig.newProjectBundleIdPrefix
    var deploymentTarget: String = AppConfig.newProjectDeploymentTarget

    private static let folderCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
    private static let identifierCharacterSet = CharacterSet.alphanumerics
    private static let bundlePrefixCharacterSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
    private static let deploymentCharacterSet = CharacterSet(charactersIn: "0123456789.")
    private static let fallbackTargetName = "MyNewApp"

    private var trimmedProjectName: String {
        projectName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var folderName: String {
        let filtered = Self.filter(trimmedProjectName, allowed: Self.folderCharacterSet)
        let condensed = filtered
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return condensed.isEmpty ? targetName : condensed
    }

    var targetName: String {
        let components = trimmedProjectName
            .components(separatedBy: Self.identifierCharacterSet.inverted)
            .filter { !$0.isEmpty }
            .map { component in
                component.prefix(1).uppercased() + component.dropFirst()
            }
        let combined = components.joined()
        return combined.isEmpty ? Self.fallbackTargetName : combined
    }

    private var sanitizedBundlePrefix: String {
        let trimmed = bundleIdPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = Self.filter(trimmed, allowed: Self.bundlePrefixCharacterSet)
        return filtered.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private var bundleSuffix: String {
        let filtered = Self.filter(trimmedProjectName.lowercased(), allowed: Self.identifierCharacterSet)
        if !filtered.isEmpty {
            return filtered.lowercased()
        }
        return targetName.lowercased()
    }

    private var filteredDeploymentTarget: String {
        Self.filter(deploymentTarget, allowed: Self.deploymentCharacterSet)
    }

    private var deploymentTargetValue: String {
        let filtered = filteredDeploymentTarget
        return filtered.isEmpty ? "17.0" : filtered
    }

    var bundleIdentifier: String {
        guard !sanitizedBundlePrefix.isEmpty else { return "" }
        return "\(sanitizedBundlePrefix).\(bundleSuffix)"
    }

    var validationMessage: String? {
        if trimmedProjectName.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Enter a project name using letters or numbers."
        }
        if sanitizedBundlePrefix.isEmpty {
            return "Bundle ID prefix can only contain letters, numbers, dots, and hyphens."
        }
        if filteredDeploymentTarget.isEmpty {
            return "Specify an iOS deployment target (for example 17.0)."
        }
        return nil
    }

    var isValid: Bool {
        validationMessage == nil
    }

    func buildRequest() -> ProjectManager.NewProjectRequest {
        ProjectManager.NewProjectRequest(
            displayName: folderName,
            folderName: folderName,
            targetName: targetName,
            bundleIDPrefix: sanitizedBundlePrefix,
            bundleIdentifier: bundleIdentifier,
            deploymentTarget: deploymentTargetValue
        )
    }

    private static func filter(_ value: String, allowed: CharacterSet) -> String {
        var filtered = ""
        for scalar in value.unicodeScalars {
            if allowed.contains(scalar) {
                filtered.append(String(scalar))
            }
        }
        return filtered
    }
}

#Preview {
    ProjectListView()
}
