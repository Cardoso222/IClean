//
//  ContentView.swift
//  IClean
//
//  Created by Paulo  Henrique on 21/11/24.
//

import SwiftUI
import Foundation

struct PieChartView: View {
    let percentage: Double
    let usedColor: Color
    let freeColor: Color
    @State private var isHovering = false
    
    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2
                let fullCircle = Path { path in
                    path.addArc(center: center,
                               radius: radius,
                               startAngle: .degrees(0),
                               endAngle: .degrees(360),
                               clockwise: false)
                }
                
                context.fill(fullCircle, with: .color(freeColor))
                
                if percentage > 0 {
                    let usedPath = Path { path in
                        path.move(to: center)
                        path.addArc(center: center,
                                   radius: radius,
                                   startAngle: .degrees(0),
                                   endAngle: .degrees(360 * percentage),
                                   clockwise: false)
                        path.closeSubpath()
                    }
                    context.fill(usedPath, with: .color(usedColor))
                }
            }
            
            if isHovering {
                Text("\(Int(percentage * 100))% Used")
                    .font(.title2)
                    .bold()
                    .foregroundColor(.primary)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

struct DiskSpace {
    let total: Int64
    let used: Int64
    let free: Int64
    
    var usedPercentage: Double {
        Double(used) / Double(total)
    }
    
    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
    
    var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: used, countStyle: .file)
    }
    
    var formattedFree: String {
        ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
    }
    
    static func current() -> DiskSpace? {
        let fileURL = URL(fileURLWithPath: "/")
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            guard let total = values.volumeTotalCapacity,
                  let free = values.volumeAvailableCapacity else { return nil }
            
            return DiskSpace(
                total: Int64(total),
                used: Int64(total - free),
                free: Int64(free)
            )
        } catch {
            print("Error getting disk space: \(error)")
            return nil
        }
    }
    
    static func emptyTrash() throws {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let trashURL = homeDirectory.appendingPathComponent(".Trash")
        
        guard let trashedItems = try? fileManager.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: nil
        ) else { return }
        
        for item in trashedItems {
            try fileManager.removeItem(at: item)
        }
    }
}

struct FileItem: Identifiable {
    let id = UUID()
    let path: String
    let size: Int64
    let modificationDate: Date
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

struct SystemPaths {
    static let protectedPaths = [
        "/System",
        "/Library",
        "/usr",
        "/bin",
        "/sbin",
        "/private",
        "/etc",
        "/var",
        "/Applications"
    ]
    
    static func isProtectedPath(_ path: String) -> Bool {
        protectedPaths.contains { path.hasPrefix($0) }
    }
}

struct ContentView: View {
    @State private var files: [FileItem] = []
    @State private var isScanning = false
    @State private var selectedPath: String?
    @State private var scannedItemsCount = 0
    @State private var currentScannedPath = ""
    @State private var selectedFiles: Set<UUID> = []
    @State private var showingDeleteConfirmation = false
    @State private var selectionMode = false
    @State private var selectedFolder: URL?
    @State private var diskSpace: DiskSpace?
    @State private var timer: Timer?
    @State private var isEmptyingTrash = false
    @State private var showTrashAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Storage Overview Section
            VStack(spacing: 16) {
                if let diskSpace = diskSpace {
                    HStack(spacing: 30) {
                        PieChartView(
                            percentage: diskSpace.usedPercentage,
                            usedColor: .blue,
                            freeColor: .green
                        )
                        .frame(width: 120, height: 120)
                        .padding(.vertical, 10)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            StorageRow(
                                label: "Total Space",
                                value: diskSpace.formattedTotal,
                                color: .purple.opacity(0.8)
                            )
                            StorageRow(
                                label: "Used Space",
                                value: diskSpace.formattedUsed,
                                color: .blue.opacity(0.8)
                            )
                            StorageRow(
                                label: "Free Space",
                                value: diskSpace.formattedFree,
                                color: .green.opacity(0.8)
                            )
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(20)
                    .background(Color(.windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            
            // Toolbar Section
            HStack(spacing: 16) {
                Text("IClean")
                    .font(.title2)
                    .bold()
                Spacer()
                
                Button(action: { showTrashAlert = true }) {
                    Label("Empty Trash", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(isEmptyingTrash)
                
                Button(action: showFolderPicker) {
                    Label(selectedFolder?.lastPathComponent ?? "Select Folder",
                          systemImage: "folder.badge.plus")
                        .lineLimit(1)
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.bordered)
                
                if !selectedFiles.isEmpty {
                    Button(action: { showingDeleteConfirmation = true }) {
                        Label("Delete (\(selectedFiles.count))", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
                
                Toggle(isOn: $selectionMode) {
                    Label("Select", systemImage: "checkmark.circle")
                }
                .toggleStyle(.button)
                .disabled(files.isEmpty)
                
                Button(action: scanFiles) {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning || selectedFolder == nil)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
            
            // Main Content Area
            if selectedFolder == nil && !isScanning {
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("Select a folder to scan")
                        .font(.title3)
                        .bold()
                    Text("Choose a folder to analyze its contents")
                        .foregroundColor(.secondary)
                    Button("Choose Folder") {
                        showFolderPicker()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.windowBackgroundColor))
            } else {
                if isScanning {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding(.bottom, 10)
                        
                        Text("Scanning files...")
                            .font(.title3)
                            .bold()
                        
                        Text("\(scannedItemsCount) items found")
                            .foregroundColor(.secondary)
                        
                        Text(currentScannedPath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 400)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.windowBackgroundColor))
                } else {
                    if files.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            Text("No large files found")
                                .font(.title3)
                                .bold()
                            Text("Try scanning a different folder")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.windowBackgroundColor))
                    } else {
                        List {
                            ForEach(files) { file in
                                FileRowMac(
                                    file: file,
                                    isSelected: selectedFiles.contains(file.id),
                                    selectionMode: selectionMode,
                                    onSelect: {
                                        if selectedFiles.contains(file.id) {
                                            selectedFiles.remove(file.id)
                                        } else {
                                            selectedFiles.insert(file.id)
                                        }
                                    },
                                    onReveal: { revealInFinder(path: file.path) },
                                    onDelete: {
                                        selectedFiles = [file.id]
                                        showingDeleteConfirmation = true
                                    }
                                )
                            }
                        }
                        .background(Color(.windowBackgroundColor))
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .alert("Delete Files", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                // Do nothing
            }
            Button("Delete", role: .destructive) {
                deleteSelectedFiles()
            }
        } message: {
            Text("Are you sure you want to delete \(selectedFiles.count) selected file\(selectedFiles.count == 1 ? "" : "s")? This action cannot be undone.")
        }
        .alert("Empty Trash", isPresented: $showTrashAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Empty Trash", role: .destructive) {
                emptyTrash()
            }
        } message: {
            Text("Are you sure you want to permanently erase the items in the Trash? This action cannot be undone.")
        }
        .onAppear {
            updateDiskSpace()
            // Update disk space every 5 seconds
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                updateDiskSpace()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    private func scanFiles() {
        guard let folderURL = selectedFolder else { return }
        
        if SystemPaths.isProtectedPath(folderURL.path) {
            return
        }
        
        isScanning = true
        scannedItemsCount = 0
        files.removeAll()
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            
            var scannedFiles: [FileItem] = []
            
            if let enumerator = fileManager.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if SystemPaths.isProtectedPath(fileURL.path) {
                        enumerator.skipDescendants()
                        continue
                    }
                    
                    DispatchQueue.main.async {
                        currentScannedPath = fileURL.path
                    }
                    
                    do {
                        let attributes = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                        if let fileSize = attributes.fileSize,
                           let modDate = attributes.contentModificationDate,
                           fileSize > 100_000_000 { // Only files larger than 100MB
                            let fileItem = FileItem(
                                path: fileURL.path,
                                size: Int64(fileSize),
                                modificationDate: modDate
                            )
                            scannedFiles.append(fileItem)
                            DispatchQueue.main.async {
                                scannedItemsCount = scannedFiles.count
                            }
                        }
                    } catch {
                        print("Error scanning file: \(error)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                files = scannedFiles.sorted(by: { $0.size > $1.size })
                isScanning = false
            }
        }
    }
    
    private func deleteSelectedFiles() {
        let filesToDelete = files.filter { selectedFiles.contains($0.id) }
        for file in filesToDelete {
            do {
                try FileManager.default.removeItem(atPath: file.path)
                files.removeAll(where: { $0.id == file.id })
            } catch {
                print("Error deleting file: \(error)")
            }
        }
        selectedFiles.removeAll()
    }
    
    private func revealInFinder(path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
    
    private func updateDiskSpace() {
        diskSpace = DiskSpace.current()
    }
    
    private func showFolderPicker() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = false
        openPanel.prompt = "Select Folder"
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                DispatchQueue.main.async {
                    selectedFolder = url
                }
            }
        }
    }
    
    private func emptyTrash() {
        isEmptyingTrash = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try DiskSpace.emptyTrash()
                DispatchQueue.main.async {
                    updateDiskSpace() // Update the disk space after emptying trash
                    isEmptyingTrash = false
                }
            } catch {
                print("Error emptying trash: \(error)")
                DispatchQueue.main.async {
                    isEmptyingTrash = false
                }
            }
        }
    }
}

struct FileRowMac: View {
    let file: FileItem
    let isSelected: Bool
    let selectionMode: Bool
    let onSelect: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .imageScale(.large)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(URL(fileURLWithPath: file.path).lastPathComponent)
                    .font(.headline)
                HStack {
                    Text(file.formattedSize)
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    Spacer()
                    Text(file.modificationDate, style: .date)
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
                Text(file.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectionMode {
                onSelect()
            }
        }
        .contextMenu {
            if selectionMode {
                Button(action: onSelect) {
                    Label(isSelected ? "Deselect" : "Select",
                          systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                }
            }
            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            Button(action: onReveal) {
                Label("Show in Finder", systemImage: "folder")
            }
        }
    }
}

struct StorageRow: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 20)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .bold()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ContentView()
}
