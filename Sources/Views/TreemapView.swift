import SwiftUI

struct TreemapItem: Identifiable {
    let id = UUID()
    let node: DiskNode
    let rect: CGRect
    let depth: Int
    let color: Color
}

struct TreemapView: View {
    let rootNode: DiskNode
    @EnvironmentObject var viewModel: MainViewModel

    // Drill down stack
    @State private var currentRoot: DiskNode?
    @State private var pathHistory: [DiskNode] = []
    
    // Hover state
    @State private var hoveredItemId: UUID?
    
    // Cached layout items to prevent recalculation on every hover frame
    @State private var layoutItems: [TreemapItem] = []

    var body: some View {
        let activeRoot = currentRoot ?? rootNode

        VStack(spacing: 0) {
            // Breadcrumb bar
            breadcrumbBar(activeRoot: activeRoot)

            Divider()

            if let children = activeRoot.children, !children.isEmpty {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        ForEach(layoutItems) { item in
                            treemapItemCell(item: item)
                        }
                    }
                    .onAppear {
                        recalculateLayout(size: geometry.size, node: activeRoot)
                    }
                    .onChange(of: geometry.size) { newSize in
                        recalculateLayout(size: newSize, node: activeRoot)
                    }
                    .onChange(of: activeRoot) { newNode in
                        recalculateLayout(size: geometry.size, node: newNode)
                    }
                }
                .padding()
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "folder.badge.minus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("This folder is empty or has no child files.")
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            // Reset drill-down if the scan root changes
            if currentRoot == nil || !isDescendantOfRoot(currentRoot!) {
                currentRoot = rootNode
                pathHistory.removeAll()
            }
        }
        .onChange(of: rootNode) { newRoot in
            currentRoot = newRoot
            pathHistory.removeAll()
        }
    }

    private func recalculateLayout(size: CGSize, node: DiskNode) {
        guard size.width > 0, size.height > 0 else { return }
        let rect = CGRect(origin: .zero, size: size)
        self.layoutItems = calculateLayout(rect: rect, node: node, depth: 0, maxDepth: 2)
    }

    // MARK: - Views

    private func breadcrumbBar(activeRoot: DiskNode) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Root button
                Button(action: {
                    drillTo(node: rootNode, historyIndex: -1)
                }) {
                    Text(rootNode.url.lastPathComponent)
                        .fontWeight(activeRoot.id == rootNode.id ? .bold : .regular)
                }
                .buttonStyle(.plain)
                .foregroundColor(activeRoot.id == rootNode.id ? .primary : .accentColor)

                ForEach(0..<pathHistory.count, id: \.self) { index in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    let node = pathHistory[index]
                    Button(action: {
                        drillTo(node: node, historyIndex: index)
                    }) {
                        Text(node.name)
                            .fontWeight(activeRoot.id == node.id ? .bold : .regular)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(activeRoot.id == node.id ? .primary : .accentColor)
                }
            }
            .padding()
        }
    }

    private func treemapItemCell(item: TreemapItem) -> some View {
        let isHovered = hoveredItemId == item.id
        let isSelected = viewModel.selectedNode?.id == item.node.id

        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(item.color.opacity(isHovered ? 0.95 : 0.8))
                .shadow(color: .black.opacity(isHovered ? 0.3 : 0.0), radius: 4)

            // Outline for selection
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(isSelected ? 0.8 : (isHovered ? 0.3 : 0.1)), lineWidth: isSelected ? 2 : 1)

            // Label text if rectangle is big enough
            if item.rect.width > 60 && item.rect.height > 35 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.node.name)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(FileSizeFormatter.format(item.node.allocatedSize))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: max(0, item.rect.width), height: max(0, item.rect.height))
        .offset(x: item.rect.minX, y: item.rect.minY)
        .onHover { hovering in
            hoveredItemId = hovering ? item.id : nil
        }
        .onTapGesture {
            viewModel.selectedNode = item.node
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if item.node.isDirectory && !item.node.name.hasPrefix("[") {
                    pathHistory.append(item.node)
                    currentRoot = item.node
                }
            }
        )
        .help("\(item.node.name) - \(FileSizeFormatter.format(item.node.allocatedSize))")
    }

    // MARK: - Logic

    private func drillTo(node: DiskNode, historyIndex: Int) {
        currentRoot = node
        if historyIndex == -1 {
            pathHistory.removeAll()
        } else {
            pathHistory = Array(pathHistory.prefix(historyIndex + 1))
        }
    }

    private func isDescendantOfRoot(_ node: DiskNode) -> Bool {
        // Simple safety check to see if node belongs to rootNode tree path
        return node.url.path.hasPrefix(rootNode.url.path)
    }

    private func calculateLayout(rect: CGRect, node: DiskNode, depth: Int, maxDepth: Int) -> [TreemapItem] {
        guard let children = node.children, !children.isEmpty else {
            return [TreemapItem(node: node, rect: rect, depth: depth, color: colorForNode(node))]
        }

        // If too deep or area is tiny, stop recursive division
        if depth >= maxDepth || rect.width < 50 || rect.height < 50 {
            return [TreemapItem(node: node, rect: rect, depth: depth, color: colorForNode(node))]
        }

        let validChildren = children.filter { $0.allocatedSize > 0 }
        let totalSize = validChildren.reduce(0) { $0 + $1.allocatedSize }
        
        guard totalSize > 0 else { return [] }

        // Layout using Squarified Treemap algorithm
        let layoutResults = SquarifiedTreemap.layout(rect: rect, nodes: validChildren)
        
        var items: [TreemapItem] = []
        for result in layoutResults {
            let child = result.node
            let childRect = result.rect
            let insetRect = childRect.insetBy(dx: 1.5, dy: 1.5)

            if child.isDirectory && insetRect.width > 60 && insetRect.height > 60 && !child.name.hasPrefix("[") {
                let subLayout = calculateLayout(rect: insetRect, node: child, depth: depth + 1, maxDepth: maxDepth)
                items.append(contentsOf: subLayout)
            } else {
                items.append(TreemapItem(node: child, rect: insetRect, depth: depth, color: colorForNode(child)))
            }
        }

        return items
    }

    private func colorForNode(_ node: DiskNode) -> Color {
        if node.name.hasPrefix("[") {
            return Color.gray.opacity(0.3)
        }
        if node.isDirectory {
            if node.isPackage {
                return Color.purple
            }
            return Color.blue
        }

        let ext = node.url.pathExtension.lowercased()
        switch ext {
        case "mp4", "mkv", "mov", "avi", "mp3", "wav", "flac", "png", "jpg", "jpeg", "gif", "psd", "ai":
            return Color.orange
        case "zip", "tar", "gz", "bz2", "xz", "7z", "dmg", "pkg", "iso":
            return Color.green
        case "pdf", "docx", "xlsx", "pptx", "txt", "md", "csv", "json":
            return Color.teal
        case "swift", "h", "m", "cpp", "c", "py", "js", "ts", "rs", "go", "java", "kt", "html", "css", "sh":
            return Color.indigo
        default:
            // Deterministic selection based on name
            let hash = abs(node.name.hashValue)
            let colors: [Color] = [.teal, .pink, .indigo, .mint, .cyan]
            return colors[hash % colors.count]
        }
    }
}

// MARK: - Squarified Treemap Layout Engine

struct SquarifiedTreemap {
    struct LayoutResult {
        let node: DiskNode
        let rect: CGRect
    }

    static func layout(rect: CGRect, nodes: [DiskNode]) -> [LayoutResult] {
        let validNodes = nodes.filter { $0.allocatedSize > 0 }
        guard !validNodes.isEmpty, rect.width > 0, rect.height > 0 else { return [] }

        let totalValue = Double(validNodes.reduce(0) { $0 + $1.allocatedSize })
        let totalArea = Double(rect.width * rect.height)
        
        // Convert node sizes to areas proportional to totalArea
        let elements = validNodes.map { node -> (DiskNode, Double) in
            let area = (Double(node.allocatedSize) / totalValue) * totalArea
            return (node, area)
        }

        return squarify(rect: rect, elements: elements)
    }

    private static func squarify(rect: CGRect, elements: [(DiskNode, Double)]) -> [LayoutResult] {
        var results: [LayoutResult] = []
        var remainingRect = rect
        var currentElements = elements

        while !currentElements.isEmpty {
            let shortestEdge = min(remainingRect.width, remainingRect.height)
            if shortestEdge <= 0 { break }

            var row: [(DiskNode, Double)] = []
            row.append(currentElements.removeFirst())

            while !currentElements.isEmpty {
                let nextElement = currentElements.first!
                var testRow = row
                testRow.append(nextElement)

                let currentWorst = worstAspectRatio(row: row, edge: shortestEdge)
                let testWorst = worstAspectRatio(row: testRow, edge: shortestEdge)

                if testWorst <= currentWorst {
                    row.append(currentElements.removeFirst())
                } else {
                    break
                }
            }

            // Layout the current row
            let rowArea = row.reduce(0.0) { $0 + $1.1 }
            let isWidthLarger = remainingRect.width >= remainingRect.height
            let rowThickness = CGFloat(rowArea) / shortestEdge
            
            var offset: CGFloat = 0.0
            for (node, area) in row {
                let length = CGFloat(area) / rowThickness
                let cellRect: CGRect
                
                if isWidthLarger {
                    // Lay out vertically (a column on the left)
                    cellRect = CGRect(x: remainingRect.minX, y: remainingRect.minY + offset, width: rowThickness, height: length)
                } else {
                    // Lay out horizontally (a row at the top)
                    cellRect = CGRect(x: remainingRect.minX + offset, y: remainingRect.minY, width: length, height: rowThickness)
                }
                
                results.append(LayoutResult(node: node, rect: cellRect))
                offset += length
            }

            // Update remainingRect
            if isWidthLarger {
                // Slice off the left column
                remainingRect = CGRect(
                    x: remainingRect.minX + rowThickness,
                    y: remainingRect.minY,
                    width: remainingRect.width - rowThickness,
                    height: remainingRect.height
                )
            } else {
                // Slice off the top row
                remainingRect = CGRect(
                    x: remainingRect.minX,
                    y: remainingRect.minY + rowThickness,
                    width: remainingRect.width,
                    height: remainingRect.height - rowThickness
                )
            }
        }

        return results
    }

    private static func worstAspectRatio(row: [(DiskNode, Double)], edge: CGFloat) -> Double {
        if row.isEmpty { return Double.infinity }
        let sumArea = row.reduce(0.0) { $0 + $1.1 }
        if sumArea == 0 { return Double.infinity }
        
        let edgeSquared = Double(edge * edge)
        let minArea = row.map { $0.1 }.min() ?? 0.0
        let maxArea = row.map { $0.1 }.max() ?? 0.0
        
        let r1 = (edgeSquared * maxArea) / (sumArea * sumArea)
        let r2 = (sumArea * sumArea) / (edgeSquared * minArea)
        
        return max(r1, r2)
    }
}
