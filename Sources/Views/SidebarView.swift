import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject var viewModel: MainViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sidebarSection("Disk Analysis")
                    sidebarButton("Home Folder", systemImage: "house", selection: .home)
                    sidebarButton("Downloads", systemImage: "arrow.down.circle", selection: .downloads)
                    sidebarButton("Desktop", systemImage: "desktopcomputer", selection: .desktop)

                    if case .customFolder(let url) = viewModel.sidebarSelection {
                        sidebarButton(url.lastPathComponent, systemImage: "folder", selection: .customFolder(url))
                    }

                    sidebarSection("Tools")
                        .padding(.top, 6)
                    sidebarButton("Developer Cleaner", systemImage: "hammer", selection: .developerCleaner)
                    sidebarButton("Browser Cleaner", systemImage: "globe", selection: .browserCleaner)
                    sidebarButton("Large Model Cleaner", systemImage: "brain", selection: .largeModelCleaner)
                    sidebarButton("App Leftovers", systemImage: "app.badge", selection: .appLeftovers)

                    sidebarSection("Application")
                        .padding(.top, 6)
                    sidebarButton("Settings", systemImage: "gearshape", selection: .settings)
                }
                .padding(.horizontal, 10)
                .padding(.top, 16)
            }

            Button(action: selectCustomFolder) {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Analyze Folder...")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func sidebarSection(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
    }

    private func sidebarButton(_ title: String, systemImage: String, selection: SidebarSelection) -> some View {
        Button(action: {
            viewModel.sidebarSelection = selection
        }) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(viewModel.sidebarSelection == selection ? Color.accentColor.opacity(0.16) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func selectCustomFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Folder to Analyze"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.sidebarSelection = .customFolder(url)
            viewModel.startScan(for: url)
        }
    }
}
