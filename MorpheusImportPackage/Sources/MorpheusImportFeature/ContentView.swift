import SwiftUI
import CoreBluetooth

public struct ContentView: View {
    @State private var bluetoothManager = BluetoothManager()
    @State private var healthKitManager = HealthKitManager()
    @State private var workoutExplorer = WorkoutExplorer()
    @State private var showDataLogs = false
    @State private var showSessions = false
    @State private var showWorkoutExplorer = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Status Section
                statusSection
                
                // Device List
                deviceList
                
                // Action Buttons
                actionButtons
            }
            .navigationTitle("Morpheus Import")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("Explorer") {
                        showWorkoutExplorer = true
                    }
                    .disabled(bluetoothManager.connectedDevice == nil)
                    
                    Button("Files") {
                        showSessions = true
                    }
                    
                    Button("Logs") {
                        showDataLogs = true
                    }
                    .disabled(bluetoothManager.dataLogs.isEmpty)
                }
            }
            .sheet(isPresented: $showDataLogs) {
                DataLogsView(bluetoothManager: bluetoothManager)
            }
            .sheet(isPresented: $showSessions) {
                SessionFilesView(bluetoothManager: bluetoothManager)
            }
            .sheet(isPresented: $showWorkoutExplorer) {
                WorkoutExplorerView(
                    workoutExplorer: workoutExplorer,
                    connectedPeripheral: bluetoothManager.connectedPeripheral
                )
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
            .task {
                await requestHealthKitAuthorization()
            }
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var statusSection: some View {
        VStack(spacing: 12) {
            // Bluetooth Status
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundColor(bluetoothStatusColor)
                Text("Bluetooth: \(bluetoothStatusText)")
                    .font(.headline)
            }
            
            // HealthKit Status
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(healthKitManager.isAuthorized ? .green : .red)
                Text("HealthKit: \(healthKitManager.isAuthorized ? "Authorized" : "Not Authorized")")
                    .font(.headline)
            }
            
            // Connected Device
            if let device = bluetoothManager.connectedDevice {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Connected: \(device.name)")
                        .font(.headline)
                }
                
                if let heartRate = bluetoothManager.lastHeartRate {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                        Text("\(heartRate) BPM")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                    }
                }
                
                // Current Session Status
                if let sessionID = bluetoothManager.currentSessionID {
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.blue)
                        Text("Recording: \(sessionID)")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Discovered Devices")
                .font(.headline)
                .padding(.horizontal)
            
            if bluetoothManager.discoveredDevices.isEmpty && bluetoothManager.isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning for devices...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(bluetoothManager.discoveredDevices) { device in
                            DeviceRow(
                                device: device,
                                isConnected: bluetoothManager.connectedDevice?.id == device.id,
                                onTap: {
                                    bluetoothManager.connect(to: device)
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if bluetoothManager.isScanning {
                Button(action: {
                    bluetoothManager.stopScanning()
                }) {
                    Label("Stop Scanning", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button(action: {
                    bluetoothManager.startScanning()
                }) {
                    Label("Start Scanning", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(bluetoothManager.bluetoothState != .poweredOn)
            }
            
            if bluetoothManager.connectedDevice != nil {
                Button(action: {
                    bluetoothManager.disconnect()
                }) {
                    Label("Disconnect", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Helper Properties
    
    private var bluetoothStatusColor: Color {
        switch bluetoothManager.bluetoothState {
        case .poweredOn: return .green
        case .poweredOff: return .red
        case .unauthorized: return .orange
        default: return .gray
        }
    }
    
    private var bluetoothStatusText: String {
        switch bluetoothManager.bluetoothState {
        case .poweredOn: return "On"
        case .poweredOff: return "Off"
        case .unauthorized: return "Unauthorized"
        case .unsupported: return "Unsupported"
        case .unknown: return "Unknown"
        case .resetting: return "Resetting"
        @unknown default: return "Unknown"
        }
    }
    
    // MARK: - Helper Methods
    
    private func requestHealthKitAuthorization() async {
        do {
            try await healthKitManager.requestAuthorization()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Device Row View

struct DeviceRow: View {
    let device: DiscoveredDevice
    let isConnected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(device.name)
                            .font(.headline)
                        
                        if device.isMorpheus {
                            Text("MORPHEUS")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text("RSSI: \(device.rssi) dBm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Data Logs View

struct DataLogsView: View {
    let bluetoothManager: BluetoothManager
    @Environment(\.dismiss) private var dismiss
    @State private var exportedLogs = ""
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationStack {
            List(bluetoothManager.dataLogs.reversed()) { log in
                VStack(alignment: .leading, spacing: 4) {
                    Text(log.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("UUID: \(log.characteristicUUID)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(log.hexString)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Data Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Export") {
                        exportedLogs = bluetoothManager.exportLogs()
                        showShareSheet = true
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [exportedLogs])
        }
    }
}

// MARK: - Session Files View

struct SessionFilesView: View {
    let bluetoothManager: BluetoothManager
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [String] = []
    @State private var showShareSheet = false
    @State private var filesToShare: [URL] = []
    
    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Data Sessions",
                        systemImage: "doc.circle",
                        description: Text("Connect to a device to start recording data")
                    )
                } else {
                    ForEach(sessions, id: \.self) { session in
                        SessionRowView(
                            sessionID: session,
                            bluetoothManager: bluetoothManager,
                            onExport: { urls in
                                filesToShare = urls
                                showShareSheet = true
                            },
                            onDelete: {
                                Task {
                                    await bluetoothManager.deleteSession(session)
                                    loadSessions()
                                }
                            }
                        )
                    }
                }
                
                Section {
                    HStack {
                        Image(systemName: "folder")
                        Text("Data Directory")
                        Spacer()
                        Button("Open") {
                            let url = bluetoothManager.getDataDirectoryURL()
                            filesToShare = [url]
                            showShareSheet = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .navigationTitle("Data Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        loadSessions()
                    }
                }
            }
            .onAppear {
                loadSessions()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: filesToShare.map { $0 as Any })
        }
    }
    
    private func loadSessions() {
        sessions = bluetoothManager.getAllSessions()
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let sessionID: String
    let bluetoothManager: BluetoothManager
    let onExport: ([URL]) -> Void
    let onDelete: () -> Void
    
    @State private var showDeleteAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(sessionName)
                    .font(.headline)
                Spacer()
                Text(sessionDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Button(action: exportSession) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
                
                Button(action: { showDeleteAlert = true }) {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }
        }
        .padding(.vertical, 4)
        .alert("Delete Session", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete this session? This action cannot be undone.")
        }
    }
    
    private var sessionName: String {
        let components = sessionID.components(separatedBy: "_")
        return components.first ?? sessionID
    }
    
    private var sessionDate: String {
        let components = sessionID.components(separatedBy: "_")
        if components.count >= 3 {
            let dateString = "\(components[1])_\(components[2])"
            // Try to parse the ISO date format
            if let date = parseSessionDate(dateString) {
                return date.formatted(date: .abbreviated, time: .shortened)
            }
        }
        return "Unknown Date"
    }
    
    private func parseSessionDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateString.replacingOccurrences(of: "_", with: "T") + "Z")
    }
    
    private func exportSession() {
        let urls = bluetoothManager.exportSessionFiles(sessionID)
        onExport(urls)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Workout Explorer View

struct WorkoutExplorerView: View {
    @ObservedObject var workoutExplorer: WorkoutExplorer
    let connectedPeripheral: CBPeripheral?
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let peripheral = connectedPeripheral {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("🔍 Workout Protocol Explorer")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Device: \(peripheral.name ?? "Unknown")")
                            .font(.headline)
                        
                        Text("This tool will systematically test commands to discover the workout download protocol.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    if workoutExplorer.isExploring {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            
                            Text("Exploring workout protocol...")
                                .font(.headline)
                            
                            Text("Testing \(workoutExplorer.explorationLog.count) commands across multiple characteristics")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    } else {
                        VStack(spacing: 16) {
                            Button(action: startExploration) {
                                Label("Start Exploration", systemImage: "magnifyingglass")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            
                            if !workoutExplorer.explorationLog.isEmpty {
                                Button(action: { showShareSheet = true }) {
                                    Label("Export Log", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                            }
                        }
                    }
                    
                    if !workoutExplorer.explorationLog.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(workoutExplorer.explorationLog.indices, id: \.self) { index in
                                    Text(workoutExplorer.explorationLog[index])
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding()
                        }
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    
                    Spacer()
                } else {
                    ContentUnavailableView(
                        "No Device Connected",
                        systemImage: "bluetooth.slash",
                        description: Text("Connect to a Morpheus device first")
                    )
                }
            }
            .padding()
            .navigationTitle("Workout Explorer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                
                if workoutExplorer.isExploring {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Stop") {
                            workoutExplorer.stopExploration()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [workoutExplorer.getLogText()])
        }
    }
    
    private func startExploration() {
        guard let peripheral = connectedPeripheral else { return }
        workoutExplorer.startExploration(peripheral: peripheral)
    }
}