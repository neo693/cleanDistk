import SwiftUI

struct BrowserCleanerView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var checkedIds = Set<String>()
    @State private var showingConfirmBulk = false
    @State private var cleaningItem: CleanerItem?
    @State private var cleanError: String? = nil

    private var cleanableSafeSize: Int64 {
        viewModel.browserItems
            .filter { checkedIds.contains($0.id) }
            .reduce(0) { $0 + ($1.detectedSize ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            if viewModel.isScanningBrowser {
                scanningStateView
            } else {
                browserListView
            }
        }
        .onAppear {
            initCheckedItems()
            if viewModel.browserItems.first?.detectedSize == nil {
                viewModel.startScanBrowser()
            }
        }
        .onChange(of: viewModel.browserItems) { _ in
            initCheckedItemsIfEmpty()
        }
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Browser Cleaner")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Scan browser caches, downloaded browser components, and on-device model files.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !viewModel.isScanningBrowser {
                Button(action: {
                    viewModel.startScanBrowser()
                }) {
                    Label("Scan Browsers", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private var scanningStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Scanning browser cache folders...")
                .font(.headline)
                .foregroundColor(.secondary)
            Button("Cancel", action: {
                viewModel.cancelScanBrowser()
            })
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var browserListView: some View {
        VStack(spacing: 0) {
            List {
                ForEach(viewModel.browserItems) { item in
                    browserItemRow(item: item)
                        .padding(.vertical, 6)
                }
            }

            if cleanableSafeSize > 0 {
                Divider()
                HStack {
                    Text("Total Selected for Cleanup:")
                        .font(.body)
                    Text(FileSizeFormatter.format(cleanableSafeSize))
                        .font(.headline)
                        .foregroundColor(.accentColor)

                    Spacer()

                    Button(action: {
                        showingConfirmBulk = true
                    }) {
                        Label("Clean Selected (\(checkedIds.count) folders)", systemImage: "trash.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .alert("Clean Selected Browser Data?", isPresented: $showingConfirmBulk) {
            Button("Clean", role: .destructive) {
                bulkClean()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move selected browser cache/model folders to the Trash. Bookmarks, history, passwords, and browser profiles are not targeted by these rules.")
        }
        .alert("Clean Folder?", isPresented: Binding(
            get: { cleaningItem != nil },
            set: { if !$0 { cleaningItem = nil } }
        )) {
            Button("Clean", role: .destructive) {
                if let item = cleaningItem {
                    individualClean(item: item)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let item = cleaningItem {
                Text("Are you sure you want to clean '\(item.title)'?\nPath: \(item.resolvedURL.path)\nSize: \(FileSizeFormatter.format(item.detectedSize ?? 0))")
            }
        }
        .alert("Cleanup Error", isPresented: Binding(
            get: { cleanError != nil },
            set: { if !$0 { cleanError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let err = cleanError {
                Text(err)
            }
        }
    }

    private func browserItemRow(item: CleanerItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if !(item.detectedSize ?? 0 > 0) {
                Image(systemName: "square")
                    .font(.title3)
                    .foregroundColor(.secondary.opacity(0.4))
                    .frame(width: 20)
            } else {
                Button(action: {
                    toggleCheck(item.id)
                }) {
                    Image(systemName: checkedIds.contains(item.id) ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundColor(checkedIds.contains(item.id) ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 20)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.headline)

                    riskBadge(for: item.risk)
                }

                Text(item.resolvedURL.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                if item.isScanning {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 50, height: 20)
                } else if let size = item.detectedSize {
                    if size > 0 {
                        Text(FileSizeFormatter.format(size))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)

                        Button("Clean") {
                            cleaningItem = item
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.small)
                    } else {
                        Text("Empty")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Pending")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 100, alignment: .trailing)
        }
    }

    private func riskBadge(for risk: CleanerRisk) -> some View {
        Text(risk.rawValue.capitalized)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor(for: risk).opacity(0.15))
            .foregroundColor(badgeColor(for: risk))
            .cornerRadius(4)
    }

    private func badgeColor(for risk: CleanerRisk) -> Color {
        switch risk {
        case .safe: return .green
        case .caution: return .orange
        case .danger: return .red
        }
    }

    private func initCheckedItems() {
        for item in viewModel.browserItems {
            if item.risk == .safe && (item.detectedSize ?? 0) > 0 {
                checkedIds.insert(item.id)
            }
        }
    }

    private func initCheckedItemsIfEmpty() {
        if checkedIds.isEmpty {
            initCheckedItems()
        }
    }

    private func toggleCheck(_ id: String) {
        if checkedIds.contains(id) {
            checkedIds.remove(id)
        } else {
            checkedIds.insert(id)
        }
    }

    private func individualClean(item: CleanerItem) {
        Task {
            do {
                try await viewModel.recycleBrowserItem(item)
                checkedIds.remove(item.id)
            } catch {
                cleanError = "Failed to clean \(item.title): \(error.localizedDescription)"
            }
        }
    }

    private func bulkClean() {
        let targets = viewModel.browserItems.filter { checkedIds.contains($0.id) }
        Task {
            for item in targets {
                do {
                    try await viewModel.recycleBrowserItem(item)
                    checkedIds.remove(item.id)
                } catch {
                    cleanError = "Failed to clean \(item.title): \(error.localizedDescription)"
                }
            }
        }
    }
}
