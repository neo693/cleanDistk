import SwiftUI

struct ScanProgressView: View {
    @EnvironmentObject var viewModel: MainViewModel

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .padding()

            VStack(spacing: 12) {
                Text("Analyzing Disk Space...")
                    .font(.title3)
                    .fontWeight(.semibold)

                if let url = viewModel.selectedFolderURL {
                    Text(url.path)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                // Current path (scrolling/truncating)
                Text(viewModel.scanProgress.currentScanningPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 40)
                    .frame(maxWidth: 450)
            }

            // Stats grid
            HStack(spacing: 48) {
                statColumn(
                    title: "Files Scanned",
                    value: "\(viewModel.scanProgress.filesScanned)",
                    systemImage: "doc"
                )
                statColumn(
                    title: "Directories Scanned",
                    value: "\(viewModel.scanProgress.directoriesScanned)",
                    systemImage: "folder"
                )
                statColumn(
                    title: "Size Analyzed",
                    value: FileSizeFormatter.format(viewModel.scanProgress.sizeScanned),
                    systemImage: "arrow.up.left.and.arrow.down.right.circle"
                )
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            Button(action: {
                viewModel.cancelScan()
            }) {
                Text("Cancel Scan")
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statColumn(title: String, value: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(.accentColor)
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 120)
    }
}
