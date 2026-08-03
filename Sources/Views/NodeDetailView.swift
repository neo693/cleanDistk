import SwiftUI

struct NodeDetailView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var showingConfirmTrash = false
    @State private var trashError: String? = nil

    private var safetyCategory: String {
        guard let node = viewModel.selectedNode else { return "Unknown" }
        let path = node.url.path
        
        // Danger paths
        if path == "/" || path.hasPrefix("/System") || path.hasPrefix("/usr") || path.hasPrefix("/bin") || path.hasPrefix("/sbin") || path.hasPrefix("/private") {
            return "Danger"
        }
        
        // Caution paths
        if path.contains("/Library") {
            return "Caution"
        }
        
        return "Safe"
    }

    var body: some View {
        VStack(spacing: 0) {
            if let node = viewModel.selectedNode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Large icon and Title
                        HStack(spacing: 12) {
                            Image(systemName: iconName(for: node))
                                .font(.system(size: 32))
                                .foregroundColor(node.isDirectory ? .accentColor : .secondary)

                            Text(node.name)
                                .font(.title3)
                                .fontWeight(.bold)
                                .lineLimit(2)
                        }
                        .padding(.top)

                        Divider()

                        // Meta details
                        VStack(alignment: .leading, spacing: 12) {
                            detailRow(label: "Kind", value: node.isDirectory ? (node.isPackage ? "Package Bundle" : "Folder") : "File")
                            
                            detailRow(label: "Space on Disk", value: FileSizeFormatter.format(node.allocatedSize))
                            
                            detailRow(label: "Logical Size", value: FileSizeFormatter.format(node.size))

                            if node.isDirectory {
                                detailRow(label: "Contains", value: "\(node.fileCount) files, \(node.directoryCount) folders")
                            }

                            if let modified = node.modifiedAt {
                                detailRow(label: "Last Modified", value: modified.formatted(date: .abbreviated, time: .shortened))
                            }
                        }

                        Divider()

                        // Path box
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Full Path")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(node.url.path)
                                .font(.caption)
                                .textSelection(.enabled)
                                .padding(8)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(4)
                        }

                        Divider()

                        // Safety Badge / Message
                        safetyCard

                        Spacer()
                    }
                    .padding()
                }

                // Actions Footer
                VStack(spacing: 12) {
                    Divider()

                    Button(action: {
                        viewModel.revealInFinder(url: node.url)
                    }) {
                        Label("Reveal in Finder", systemImage: "macwindow.and.keypad")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(action: {
                        showingConfirmTrash = true
                    }) {
                        Label("Move to Trash", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                    .disabled(safetyCategory == "Danger" || node.name.hasPrefix("["))
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .alert("Move to Trash?", isPresented: $showingConfirmTrash) {
                    Button("Move to Trash", role: .destructive) {
                        Task {
                            do {
                                try await viewModel.recycleNode(node)
                            } catch {
                                trashError = error.localizedDescription
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(confirmationMessage(for: node))
                }
                .alert("Error Moving to Trash", isPresented: Binding(
                    get: { trashError != nil },
                    set: { if !$0 { trashError = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    if let err = trashError {
                        Text(err)
                    }
                }
            } else {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No item selected")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Select a file or folder in the list or tree view to inspect properties and perform cleanup.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func iconName(for node: DiskNode) -> String {
        if node.name.hasPrefix("[") && node.name.hasSuffix("]") {
            return "square.grid.3x3.fill"
        }
        if node.isDirectory {
            if node.isPackage {
                return "doc.zippackage"
            }
            return "folder.fill"
        }
        return "doc"
    }

    private var safetyCard: some View {
        Group {
            switch safetyCategory {
            case "Danger":
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "xmark.shield.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Protected")
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                        Text("This folder is critical to macOS operation. Deleting it is forbidden to prevent breaking the operating system.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            case "Caution":
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Library Item")
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                        Text("This folder resides under ~/Library. It contains application cache, settings, or database records. Deleting it might sign you out of apps or clear application preferences.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            default:
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Safe User File")
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        Text("This is a standard file or folder inside user storage. It is safe to move to the Trash.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    private func confirmationMessage(for node: DiskNode) -> String {
        if safetyCategory == "Caution" {
            return "WARNING: '\(node.name)' is a system cache or configuration directory under ~/Library. Deleting it may cause configuration issues or lose local data in some apps.\n\nAre you sure you want to move it to the Trash?"
        }
        return "Are you sure you want to move '\(node.name)' (\(FileSizeFormatter.format(node.allocatedSize))) to the Trash?"
    }
}
