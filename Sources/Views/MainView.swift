import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject var viewModel: MainViewModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 240)
            
            Divider()
            
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch viewModel.sidebarSelection {
        case .developerCleaner:
            DeveloperCleanerView()
        case .browserCleaner:
            BrowserCleanerView()
        case .largeModelCleaner:
            LargeModelCleanerView()
        case .appLeftovers:
            AppLeftoverCleanerView()
        case .settings:
            SettingsView()
        case .home, .downloads, .desktop, .customFolder:
            folderAnalysisView
        }
    }

    @ViewBuilder
    private var folderAnalysisView: some View {
        if viewModel.isScanning {
            ScanProgressView()
        } else if let rootNode = viewModel.rootNode {
            HStack(spacing: 0) {
                // Main Workspace Area
                VStack(spacing: 0) {
                    // Header Toolbar
                    analysisHeaderView(rootNode: rootNode)

                    Divider()

                    if !viewModel.scanErrors.isEmpty {
                        scanErrorBanner
                        Divider()
                    }

                    // Tab Views
                    Group {
                        switch viewModel.viewMode {
                        case .fileList:
                            FileListView(rootNode: rootNode)
                        case .tree:
                            DirectoryTreeView(rootNode: rootNode)
                        case .treemap:
                            TreemapView(rootNode: rootNode)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Divider()

                // Inspector Detail Panel
                NodeDetailView()
                    .frame(width: 280)
            }
        } else {
            // Landing screen
            landingView
        }
    }

    private func analysisHeaderView(rootNode: DiskNode) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rootNode.url.lastPathComponent)
                    .font(.headline)
                Text(rootNode.url.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Picker("View Mode", selection: $viewModel.viewMode) {
                Text("File List").tag(ViewMode.fileList)
                Text("Directory Tree").tag(ViewMode.tree)
                Text("Treemap").tag(ViewMode.treemap)
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Button(action: {
                if let url = viewModel.selectedFolderURL {
                    viewModel.startScan(for: url)
                }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("Re-scan folder")
        }
        .padding()
    }

    private var scanErrorBanner: some View {
        let permissionErrors = viewModel.scanErrors.filter {
            $0.message.localizedCaseInsensitiveContains("operation not permitted")
                || $0.message.localizedCaseInsensitiveContains("permission")
        }

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(permissionErrors.isEmpty ? "Some folders could not be scanned" : "CleanDisk needs folder access")
                    .font(.headline)

                if permissionErrors.isEmpty {
                    Text("\(viewModel.scanErrors.count) scan error(s). The list may be incomplete.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("macOS blocked direct access. Click Grant Access... and select the folder, or grant CleanDisk Full Disk Access in System Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let firstError = viewModel.scanErrors.first {
                    Text("\(firstError.url.path): \(firstError.message)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if !permissionErrors.isEmpty {
                Button("Grant Access...") {
                    grantAccessToSelectedFolder()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }

    private func grantAccessToSelectedFolder() {
        let panel = NSOpenPanel()
        panel.title = "Grant CleanDisk Folder Access"
        panel.message = "Select the folder you want CleanDisk to scan."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = viewModel.selectedFolderURL

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.sidebarSelection = .customFolder(url)
            viewModel.startScan(for: url)
        }
    }

    private var landingView: some View {
        VStack(spacing: 24) {
            if #available(macOS 14.0, *) {
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.accentColor, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse, options: .repeating)
            } else {
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 8) {
                Text("CleanDisk Space Analyzer")
                    .font(.title)
                    .fontWeight(.bold)

                if let url = viewModel.selectedFolderURL {
                    Text("Ready to analyze: \(url.path)")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Select a folder in the sidebar to begin analysis")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)

            if let url = viewModel.selectedFolderURL {
                Button(action: {
                    viewModel.startScan(for: url)
                }) {
                    Text("Analyze Disk Space")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.accentColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
