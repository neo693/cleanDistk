import SwiftUI

struct AppLeftoverCleanerView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var checkedIds = Set<String>()
    @State private var showingConfirmBulk = false
    @State private var cleaningItem: CleanerItem?
    @State private var cleanError: String?

    private var selectedSize: Int64 {
        viewModel.appLeftoverItems
            .filter { checkedIds.contains($0.id) }
            .reduce(0) { $0 + ($1.detectedSize ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            if viewModel.isScanningAppLeftovers {
                scanningStateView
            } else {
                leftoversListView
            }
        }
        .onAppear {
            if viewModel.appLeftoverItems.isEmpty {
                viewModel.startScanAppLeftovers()
            }
            initCheckedItems()
        }
        .onChange(of: viewModel.appLeftoverItems) { _ in
            initCheckedItemsIfEmpty()
        }
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Uninstalled App Leftovers")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Find files whose bundle ID no longer matches an installed app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !viewModel.isScanningAppLeftovers {
                Button(action: {
                    checkedIds.removeAll()
                    viewModel.startScanAppLeftovers()
                }) {
                    Label("Scan Leftovers", systemImage: "arrow.clockwise")
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
            Text("Scanning installed apps and Library leftovers...")
                .font(.headline)
                .foregroundColor(.secondary)
            Button("Cancel", action: {
                viewModel.cancelScanAppLeftovers()
            })
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var leftoversListView: some View {
        VStack(spacing: 0) {
            if viewModel.appLeftoverItems.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(viewModel.appLeftoverItems) { item in
                        leftoverRow(item: item)
                            .padding(.vertical, 6)
                    }
                }
            }

            if selectedSize > 0 {
                Divider()
                HStack {
                    Text("Selected for Cleanup:")
                    Text(FileSizeFormatter.format(selectedSize))
                        .font(.headline)
                        .foregroundColor(.accentColor)

                    Spacer()

                    Button(action: {
                        showingConfirmBulk = true
                    }) {
                        Label("Clean Selected (\(checkedIds.count))", systemImage: "trash.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .alert("Clean Selected Leftovers?", isPresented: $showingConfirmBulk) {
            Button("Clean", role: .destructive) {
                bulkClean()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This moves selected leftover files to the Trash. Only restore from Trash if an app behaves incorrectly afterward.")
        }
        .alert("Clean Leftover?", isPresented: Binding(
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
                Text("Move this leftover to the Trash?\nPath: \(item.resolvedURL.path)\nSize: \(FileSizeFormatter.format(item.detectedSize ?? 0))")
            }
        }
        .alert("Cleanup Error", isPresented: Binding(
            get: { cleanError != nil },
            set: { if !$0 { cleanError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let cleanError {
                Text(cleanError)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No bundle-ID leftovers found")
                .font(.headline)
            Text("This scan intentionally ignores fuzzy app-name matches to avoid deleting the wrong app data.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func leftoverRow(item: CleanerItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if item.risk == .danger || !(item.detectedSize ?? 0 > 0) {
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
                Text(FileSizeFormatter.format(item.detectedSize ?? 0))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)

                Button("Clean") {
                    cleaningItem = item
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
                .disabled(item.risk == .danger)
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
        for item in viewModel.appLeftoverItems where item.risk == .safe && (item.detectedSize ?? 0) > 0 {
            checkedIds.insert(item.id)
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
                try await viewModel.recycleAppLeftoverItem(item)
                checkedIds.remove(item.id)
            } catch {
                cleanError = "Failed to clean \(item.title): \(error.localizedDescription)"
            }
        }
    }

    private func bulkClean() {
        let targets = viewModel.appLeftoverItems.filter { checkedIds.contains($0.id) }
        Task {
            for item in targets {
                do {
                    try await viewModel.recycleAppLeftoverItem(item)
                    checkedIds.remove(item.id)
                } catch {
                    cleanError = "Failed to clean \(item.title): \(error.localizedDescription)"
                }
            }
        }
    }
}
