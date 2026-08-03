import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var newPathInput = ""

    private let sizeThresholds: [(String, Int64)] = [
        ("Show All Files", 0),
        ("100 KB", Int64(100 * 1024)),
        ("500 KB", Int64(500 * 1024)),
        ("1 MB", Int64(1024 * 1024)),
        ("5 MB", Int64(5 * 1024 * 1024)),
        ("10 MB", Int64(10 * 1024 * 1024)),
        ("50 MB", Int64(50 * 1024 * 1024))
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CleanDisk Settings")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Customize scanning constraints, exclusions, and safety warning levels.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            Form {
                // Section 1: Scanning Filters
                Section("Scanning Constraints") {
                    Toggle("Skip Hidden Files and Folders", isOn: $viewModel.skipHiddenFiles)
                        .help("Skip items starting with a dot (e.g. .git, .ds_store). Highly recommended to speed up scan.")

                    Toggle("Skip Package Contents", isOn: $viewModel.skipPackages)
                        .help("Treat application bundles (.app, .xcodeproj) as files and do not scan inside them.")

                    Picker("Minimum File Display Size", selection: $viewModel.minDisplaySize) {
                        ForEach(sizeThresholds, id: \.1) { (label, value) in
                            Text(label).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .help("Files below this size will be consolidated under a single '[Small Files]' row to improve rendering performance.")
                }

                // Section 2: Excluded Directories
                Section("Excluded Scan Paths") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Excluding standard system paths prevents accidental scans of critical directories.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        List {
                            ForEach(viewModel.customIgnorePaths, id: \.self) { path in
                                HStack {
                                    Image(systemName: "folder.badge.minus")
                                        .foregroundColor(.red)
                                    Text(path)
                                        .font(.system(.body, design: .monospaced))
                                    Spacer()
                                    Button(action: {
                                        removeIgnorePath(path)
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(height: 150)
                        .cornerRadius(6)

                        // Add new ignore path input
                        HStack {
                            TextField("Enter absolute folder path to exclude (e.g. /Users/simons/Secret)", text: $newPathInput)
                                .textFieldStyle(.roundedBorder)

                            Button(action: addIgnorePath) {
                                Label("Exclude Path", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                            .disabled(newPathInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
        }
    }

    private func addIgnorePath() {
        let trimmed = newPathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Standardize path (remove trailing slashes, etc.)
        let url = URL(fileURLWithPath: trimmed)
        let standardPath = url.path

        if !viewModel.customIgnorePaths.contains(standardPath) {
            viewModel.customIgnorePaths.append(standardPath)
        }
        newPathInput = ""
    }

    private func removeIgnorePath(_ path: String) {
        viewModel.customIgnorePaths.removeAll { $0 == path }
    }
}
