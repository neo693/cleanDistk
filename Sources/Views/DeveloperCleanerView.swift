import SwiftUI

struct DeveloperCleanerView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var checkedIds = Set<String>()
    @State private var showingConfirmBulk = false
    @State private var cleaningItem: CleanerItem?
    @State private var cleanError: String? = nil

    private var cleanableSafeSize: Int64 {
        viewModel.developerItems
            .filter { checkedIds.contains($0.id) }
            .reduce(0) { $0 + ($1.detectedSize ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            if viewModel.isScanningDeveloper {
                scanningStateView
            } else {
                cachesListView
            }
        }
        .onAppear {
            // Auto check safe rules on appear
            initCheckedItems()
            // Auto scan on load if not scanned yet
            if viewModel.developerItems.first?.detectedSize == nil {
                viewModel.startScanDeveloper()
            }
        }
        .onChange(of: viewModel.developerItems) { _ in
            initCheckedItemsIfEmpty()
        }
    }

    // MARK: - Subviews

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Developer Cache Cleaner")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Scan and safely reclaim disk space from compiler caches, simulators, and package manager stores.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !viewModel.isScanningDeveloper {
                Button(action: {
                    viewModel.startScanDeveloper()
                }) {
                    Label("Scan Caches", systemImage: "arrow.clockwise")
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
            Text("Scanning developer cache folders...")
                .font(.headline)
                .foregroundColor(.secondary)
            Button("Cancel", action: {
                viewModel.cancelScanDeveloper()
            })
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cachesListView: some View {
        VStack(spacing: 0) {
            List {
                ForEach(viewModel.developerItems) { item in
                    cacheItemRow(item: item)
                        .padding(.vertical, 6)
                }
            }

            // Bulk Cleanup Actions Panel
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
        .alert("Clean Selected Caches?", isPresented: $showingConfirmBulk) {
            Button("Clean", role: .destructive) {
                bulkClean()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move the contents of the selected developer cache folders to the Trash. You can still restore them from the Trash if needed.")
        }
        .alert(cleaningItem?.isDocker == true ? "Run Docker Prune?" : "Clean Folder?", isPresented: Binding(
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
                if item.isDocker {
                    Text("Are you sure you want to run the following Docker command?\nCommand: \(item.dockerCommand ?? "")\nReclaimable Space: \(FileSizeFormatter.format(item.detectedSize ?? 0))")
                } else {
                    Text("Are you sure you want to clean '\(item.title)'?\nPath: \(item.resolvedURL.path)\nSize: \(FileSizeFormatter.format(item.detectedSize ?? 0))")
                }
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

    private func cacheItemRow(item: CleanerItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Checkbox
            if item.risk == .danger || !(item.detectedSize ?? 0 > 0) {
                // Disabled checkbox
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

                if item.isDocker {
                    if let cmd = item.dockerCommand {
                        Text(cmd)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Docker Environment")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(item.resolvedURL.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

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
                        .disabled(item.id == "docker-data")
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

    // MARK: - Logic

    private func initCheckedItems() {
        // Automatically check safe rules if they exist and are not already configured
        for item in viewModel.developerItems {
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
                try await viewModel.recycleDeveloperItem(item)
                checkedIds.remove(item.id)
            } catch {
                cleanError = "Failed to clean \(item.title): \(error.localizedDescription)"
            }
        }
    }

    private func bulkClean() {
        let targets = viewModel.developerItems.filter { checkedIds.contains($0.id) }
        Task {
            for item in targets {
                do {
                    try await viewModel.recycleDeveloperItem(item)
                    checkedIds.remove(item.id)
                } catch {
                    cleanError = "Failed to clean \(item.title): \(error.localizedDescription)"
                }
            }
        }
    }
}
