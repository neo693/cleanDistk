import SwiftUI

struct LargeModelCleanerView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var checkedIds = Set<String>()
    @State private var showingConfirmBulk = false
    @State private var cleaningItem: CleanerItem?
    @State private var cleanError: String? = nil

    private var selectedSize: Int64 {
        viewModel.largeModelItems
            .filter { checkedIds.contains($0.id) }
            .reduce(0) { $0 + ($1.detectedSize ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            if viewModel.isScanningLargeModels {
                scanningStateView
            } else {
                modelListView
            }
        }
        .onAppear {
            if viewModel.largeModelItems.isEmpty {
                viewModel.startScanLargeModels()
            }
        }
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Large Model Cleaner")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Find local LLM/checkpoint files from Ollama, Hugging Face, LM Studio, ModelScope, Torch, Whisper, and Core ML caches.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !viewModel.isScanningLargeModels {
                Button(action: {
                    checkedIds.removeAll()
                    viewModel.startScanLargeModels()
                }) {
                    Label("Scan Models", systemImage: "arrow.clockwise")
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
            Text("Scanning large model files...")
                .font(.headline)
                .foregroundColor(.secondary)
            Button("Cancel", action: {
                viewModel.cancelScanLargeModels()
            })
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var modelListView: some View {
        VStack(spacing: 0) {
            List {
                if viewModel.largeModelItems.isEmpty {
                    Text("No large model files found in known model cache folders.")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 12)
                } else {
                    ForEach(viewModel.largeModelItems) { item in
                        modelRow(item: item)
                            .padding(.vertical, 6)
                    }
                }
            }

            if selectedSize > 0 {
                Divider()
                HStack {
                    Text("Total Selected for Cleanup:")
                        .font(.body)
                    Text(FileSizeFormatter.format(selectedSize))
                        .font(.headline)
                        .foregroundColor(.accentColor)

                    Spacer()

                    Button(action: {
                        showingConfirmBulk = true
                    }) {
                        Label("Clean Selected (\(checkedIds.count) files)", systemImage: "trash.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .alert("Clean Selected Models?", isPresented: $showingConfirmBulk) {
            Button("Clean", role: .destructive) {
                bulkClean()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move selected model/checkpoint files to the Trash. Apps may need to download them again.")
        }
        .alert("Clean Model File?", isPresented: Binding(
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

    private func modelRow(item: CleanerItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: {
                toggleCheck(item.id)
            }) {
                Image(systemName: checkedIds.contains(item.id) ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(checkedIds.contains(item.id) ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)

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
                try await viewModel.recycleLargeModelItem(item)
                checkedIds.remove(item.id)
            } catch {
                cleanError = "Failed to clean \(item.title): \(error.localizedDescription)"
            }
        }
    }

    private func bulkClean() {
        let targets = viewModel.largeModelItems.filter { checkedIds.contains($0.id) }
        Task {
            for item in targets {
                do {
                    try await viewModel.recycleLargeModelItem(item)
                    checkedIds.remove(item.id)
                } catch {
                    cleanError = "Failed to clean \(item.title): \(error.localizedDescription)"
                }
            }
        }
    }
}
