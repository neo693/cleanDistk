import SwiftUI

struct DirectoryTreeView: View {
    let rootNode: DiskNode
    @EnvironmentObject var viewModel: MainViewModel
    @State private var expandedIDs = Set<UUID>()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                TreeRows(
                    nodes: rootNode.children ?? [],
                    depth: 0,
                    rootSize: rootNode.allocatedSize,
                    expandedIDs: $expandedIDs
                )
                .environmentObject(viewModel)
            }
        }
        .onAppear {
            if expandedIDs.isEmpty {
                expandedIDs.formUnion((rootNode.children ?? []).prefix(8).map(\.id))
            }
        }
    }
}

private struct TreeRows: View {
    let nodes: [DiskNode]
    let depth: Int
    let rootSize: Int64
    @Binding var expandedIDs: Set<UUID>
    @EnvironmentObject var viewModel: MainViewModel

    var body: some View {
        ForEach(nodes) { node in
            treeRow(node)

            Divider()
                .padding(.leading, CGFloat(28 + depth * 18))

            if expandedIDs.contains(node.id), let children = node.children {
                TreeRows(
                    nodes: children,
                    depth: depth + 1,
                    rootSize: rootSize,
                    expandedIDs: $expandedIDs
                )
                .environmentObject(viewModel)
            }
        }
    }

    private func treeRow(_ node: DiskNode) -> some View {
        HStack(spacing: 8) {
            Button(action: {
                toggleExpanded(node)
            }) {
                Image(systemName: hasChildren(node) ? "chevron.right" : "")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(expandedIDs.contains(node.id) ? 90 : 0))
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
            .disabled(!hasChildren(node))

            Image(systemName: iconName(for: node))
                .foregroundColor(node.isDirectory ? .accentColor : .secondary)
                .frame(width: 16)

            Text(node.name)
                .font(.body)
                .lineLimit(1)

            if let err = node.error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .help(err)
            }

            Spacer()

            Text(FileSizeFormatter.format(node.allocatedSize))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)

            if rootSize > 0 {
                let pct = Double(node.allocatedSize) / Double(rootSize)
                ProgressView(value: min(1.0, max(0.0, pct)))
                    .progressViewStyle(.linear)
                    .frame(width: 50)
                    .tint(Color.accentColor)
            }
        }
        .padding(.leading, CGFloat(10 + depth * 18))
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .background(viewModel.selectedNode?.id == node.id ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedNode = node
        }
        .onTapGesture(count: 2) {
            toggleExpanded(node)
        }
        .contextMenu {
            Button("Reveal in Finder") {
                viewModel.revealInFinder(url: node.url)
            }

            if !node.isDirectory {
                Button("Open Parent Folder") {
                    viewModel.openParentFolder(of: node.url)
                }
            }

            Divider()

            Button("Move to Trash") {
                DispatchQueue.main.async {
                    Task {
                        try? await viewModel.recycleNode(node)
                    }
                }
            }
            .disabled(isProtected(node: node))
        }
    }

    private func toggleExpanded(_ node: DiskNode) {
        guard hasChildren(node) else { return }
        if expandedIDs.contains(node.id) {
            expandedIDs.remove(node.id)
        } else {
            expandedIDs.insert(node.id)
        }
    }

    private func hasChildren(_ node: DiskNode) -> Bool {
        !(node.children?.isEmpty ?? true)
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

    private func isProtected(node: DiskNode) -> Bool {
        let path = node.url.path
        return path == "/" || path == "/System" || path == "/usr" || path == "/bin" || path == "/sbin"
    }
}
