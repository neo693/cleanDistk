import SwiftUI

struct FileListView: View {
    private struct FileTypeSlice: Identifiable {
        let id: String
        let label: String
        let size: Int64
        let count: Int
        let color: Color
    }

    let rootNode: DiskNode
    @EnvironmentObject var viewModel: MainViewModel
    @State private var searchText = ""
    @State private var selectedTypeID: String?
    @State private var deleteError: String?
    @State private var showingBulkDeleteConfirm = false

    private let typeColors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink, .gray
    ]

    private var flatList: [DiskNode] {
        var result: [DiskNode] = []

        func traverse(_ node: DiskNode) {
            // Skip virtual nodes
            if node.name.hasPrefix("[") && node.name.hasSuffix("]") {
                return
            }
            result.append(node)

            if let children = node.children {
                for child in children {
                    traverse(child)
                }
            }
        }

        traverse(rootNode)

        return result
            .filter { $0.id != rootNode.id }
            .sorted { $0.allocatedSize > $1.allocatedSize }
    }

    private var filteredList: [DiskNode] {
        flatList.filter { node in
            let matchesType = selectedTypeID == nil || fileTypeID(for: node) == selectedTypeID
            let matchesSearch = searchText.isEmpty || node.name.localizedCaseInsensitiveContains(searchText)
            return matchesType && matchesSearch
        }
    }

    private var deletableFilteredList: [DiskNode] {
        filteredList.filter { !isProtected(node: $0) }
    }

    private var deletableFilteredSize: Int64 {
        deletableFilteredList.reduce(Int64(0)) { $0 + $1.allocatedSize }
    }

    private var typeSlices: [FileTypeSlice] {
        let grouped = Dictionary(grouping: flatList, by: fileTypeID)
        let sortedGroups = grouped
            .map { typeID, nodes in
                (
                    typeID: typeID,
                    size: nodes.reduce(Int64(0)) { $0 + $1.allocatedSize },
                    count: nodes.count
                )
            }
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }

        return sortedGroups.enumerated().map { index, group in
            FileTypeSlice(
                id: group.typeID,
                label: fileTypeLabel(for: group.typeID),
                size: group.size,
                count: group.count,
                color: typeColors[index % typeColors.count]
            )
        }
    }

    private var selectedTypeLabel: String {
        guard let selectedTypeID else { return "All Types" }
        return fileTypeLabel(for: selectedTypeID)
    }

    var body: some View {
        VStack(spacing: 0) {
            fileTypeSummaryView

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search large files and folders...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding()

            bulkActionBar

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredList) { node in
                        fileRow(node)

                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
        .alert("Error Moving to Trash", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let deleteError {
                Text(deleteError)
            }
        }
        .alert("Move Filtered Items to Trash?", isPresented: $showingBulkDeleteConfirm) {
            Button("Move to Trash", role: .destructive) {
                bulkDeleteFiltered()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move \(deletableFilteredList.count) item(s), \(FileSizeFormatter.format(deletableFilteredSize)), to the Trash. Current type and search filters are applied.")
        }
    }

    private var fileTypeSummaryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("File Types")
                    .font(.headline)

                Text(FileSizeFormatter.format(flatList.reduce(Int64(0)) { $0 + $1.allocatedSize }))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if selectedTypeID != nil {
                    Button("All Types") {
                        selectedTypeID = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if typeSlices.isEmpty {
                Text("No files to summarize")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                typeBar

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(typeSlices.prefix(8))) { slice in
                            typeLegendButton(slice)
                        }
                        if typeSlices.count > 8 {
                            Text("+\(typeSlices.count - 8) more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Text("\(selectedTypeLabel): \(filteredList.count) item(s)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var bulkActionBar: some View {
        HStack {
            Text("\(filteredList.count) shown")
                .font(.caption)
                .foregroundColor(.secondary)

            if filteredList.count != deletableFilteredList.count {
                Text("\(filteredList.count - deletableFilteredList.count) protected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                showingBulkDeleteConfirm = true
            }) {
                Label("Clean Filtered", systemImage: "trash.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
            .disabled(deletableFilteredList.isEmpty)
            .help("Move the current filtered list to Trash")
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func fileRow(_ node: DiskNode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: node.isDirectory ? (node.isPackage ? "doc.zippackage" : "folder.fill") : "doc")
                .foregroundColor(node.isDirectory ? .accentColor : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.body)
                    .lineLimit(1)
                Text(node.url.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(FileSizeFormatter.format(node.allocatedSize))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)

            Button(action: {
                delete(node)
            }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
            .disabled(isProtected(node: node))
            .help("Move to Trash")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(viewModel.selectedNode?.id == node.id ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedNode = node
        }
        .contextMenu {
            Button("Reveal in Finder") {
                viewModel.revealInFinder(url: node.url)
            }

            Button("Open Parent Folder") {
                viewModel.openParentFolder(of: node.url)
            }

            Divider()

            Button("Move to Trash") {
                delete(node)
            }
            .disabled(isProtected(node: node))
        }
    }

    private var typeBar: some View {
        GeometryReader { geometry in
            let totalSize = max(typeSlices.reduce(Int64(0)) { $0 + $1.size }, 1)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(NSColor.separatorColor).opacity(0.25))

                ForEach(Array(typeSlices.enumerated()), id: \.element.id) { index, slice in
                    let start = typeSlices.prefix(index).reduce(Int64(0)) { $0 + $1.size }
                    let x = geometry.size.width * CGFloat(Double(start) / Double(totalSize))
                    let width = geometry.size.width * CGFloat(Double(slice.size) / Double(totalSize))

                    Rectangle()
                        .fill(slice.color.opacity(selectedTypeID == nil || selectedTypeID == slice.id ? 1 : 0.28))
                        .frame(width: width)
                        .offset(x: x)
                        .help("\(slice.label): \(FileSizeFormatter.format(slice.size))")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        selectType(at: value.location.x, width: geometry.size.width, totalSize: totalSize)
                    }
            )
        }
        .frame(height: 18)
    }

    private func typeLegendButton(_ slice: FileTypeSlice) -> some View {
        Button(action: {
            selectedTypeID = selectedTypeID == slice.id ? nil : slice.id
        }) {
            HStack(spacing: 5) {
                Circle()
                    .fill(slice.color)
                    .frame(width: 9, height: 9)

                Text(slice.label)
                    .font(.caption)

                Text(FileSizeFormatter.format(slice.size))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .opacity(selectedTypeID == nil || selectedTypeID == slice.id ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .help("\(slice.count) item(s)")
    }

    private func isProtected(node: DiskNode) -> Bool {
        let path = node.url.path
        if path == "/" || path == "/System" || path == "/usr" || path == "/bin" || path == "/sbin" {
            return true
        }
        return false
    }

    private func fileTypeID(for node: DiskNode) -> String {
        if node.isDirectory {
            return "folder"
        }

        let ext = node.url.pathExtension.lowercased()
        if ext.isEmpty {
            return "no-extension"
        }
        return ext
    }

    private func fileTypeLabel(for typeID: String) -> String {
        switch typeID {
        case "folder": return "Folders"
        case "no-extension": return "No Extension"
        default: return ".\(typeID)"
        }
    }

    private func selectType(at xPosition: CGFloat, width: CGFloat, totalSize: Int64) {
        guard width > 0 else { return }
        let clampedRatio = min(max(Double(xPosition / width), 0), 1)
        let targetSize = Double(totalSize) * clampedRatio
        var accumulated = 0.0

        for slice in typeSlices {
            accumulated += Double(slice.size)
            if targetSize <= accumulated {
                selectedTypeID = selectedTypeID == slice.id ? nil : slice.id
                return
            }
        }
    }

    private func delete(_ node: DiskNode) {
        DispatchQueue.main.async {
            Task {
                do {
                    try await viewModel.recycleNode(node)
                } catch {
                    deleteError = error.localizedDescription
                }
            }
        }
    }

    private func bulkDeleteFiltered() {
        let targets = deletableFilteredList
        DispatchQueue.main.async {
            Task {
                do {
                    try await viewModel.recycleNodes(targets)
                } catch {
                    deleteError = error.localizedDescription
                }
            }
        }
    }
}
