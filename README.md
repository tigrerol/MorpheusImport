# MorpheusImport

iOS app for reverse engineering and importing Morpheus heart rate monitor data into HealthKit

## Overview

MorpheusImport is a modern iOS application designed to connect to Morpheus heart rate monitors, capture raw Bluetooth Low Energy (BLE) data for reverse engineering purposes, and import processed heart rate data into Apple HealthKit.

## Features

### 🔬 Reverse Engineering Capabilities
- **Real-time BLE Data Capture**: Logs all characteristic updates with timestamps
- **Multiple Export Formats**: CSV (human-readable), binary files, analysis logs
- **Session Management**: Organized data collection sessions for each device connection
- **Comprehensive Logging**: Hex, ASCII, binary, and timestamped data for thorough analysis

### 💓 Heart Rate Monitoring
- **Standard BLE Support**: Compatible with standard heart rate service (0x180D)
- **HealthKit Integration**: Secure import of heart rate data to Apple Health
- **Real-time Display**: Live heart rate monitoring during connection

### 📱 Modern iOS App
- **SwiftUI Interface**: Clean, intuitive user interface
- **Swift 6 Concurrency**: Modern async/await patterns with strict concurrency compliance
- **iOS 17+ Support**: Takes advantage of latest iOS APIs and features

## Technical Architecture

### Project Structure
```
MorpheusImport/
├── MorpheusImport.xcworkspace/              # Open this file in Xcode
├── MorpheusImport.xcodeproj/                # App shell project
├── MorpheusImport/                          # App target (minimal)
│   ├── Assets.xcassets/                     # App-level assets
│   └── MorpheusImportApp.swift              # App entry point
├── MorpheusImportPackage/                   # 🚀 Primary development area
│   ├── Sources/MorpheusImportFeature/       # Feature implementation
│   │   ├── Bluetooth/BluetoothManager.swift     # BLE management
│   │   ├── HealthKit/HealthKitManager.swift     # HealthKit integration
│   │   ├── Storage/DataFileManager.swift        # File system storage
│   │   └── ContentView.swift                    # Main UI
│   └── Tests/                               # Unit tests
└── Config/                                  # Build configuration
    ├── MorpheusImport.entitlements          # App capabilities
    └── *.xcconfig                           # Build settings
```

### Key Components

**BluetoothManager**
- BLE device discovery and connection
- Raw data logging for reverse engineering
- Standard heart rate protocol parsing
- Swift 6 concurrency compliance

**HealthKitManager**  
- Secure heart rate data import
- Privacy-compliant authorization flow
- Batch data writing capabilities

**DataFileManager**
- File system storage with session management
- Multiple export formats (CSV, binary, analysis)
- Organized data structure for analysis

## Data Formats

### Raw Data Logging
- `sessionID_raw.csv` - Human-readable hex, ASCII, binary data
- `sessionID_characteristicUUID_binary.dat` - Pure binary with timestamps
- `sessionID_heartrates.csv` - Processed heart rate values
- `sessionID_analysis.txt` - Connection events and notes

### Storage Location
Files are saved to: `Documents/MorpheusData/`
Example: `Morpheus_HRM_2025-01-21T14:30:45Z_raw.csv`

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 6.1+
- Bluetooth Low Energy support
- HealthKit capability

## Setup & Installation

1. Clone the repository
2. Open `MorpheusImport.xcworkspace` in Xcode
3. Build and run on device (Simulator won't have Bluetooth)
4. Grant Bluetooth and HealthKit permissions when prompted

## Usage

1. **Start Scanning**: Tap "Start Scanning" to discover BLE heart rate monitors
2. **Connect to Device**: Select your Morpheus HRM from the discovered devices list
3. **Data Collection**: App automatically creates a new session and begins logging
4. **View Data**: Access recorded sessions via "Files" button
5. **Export Data**: Share session files for analysis in external tools

## Permissions

The app requires the following permissions:
- **Bluetooth**: To connect to Morpheus heart rate monitor  
- **HealthKit**: To read/write heart rate data
- **File System**: To save raw data for analysis

## Privacy & Security

- All data processing happens locally on device
- HealthKit data is encrypted and access-controlled by iOS
- Raw BLE data files are stored in app's sandboxed Documents directory
- No data is transmitted to external servers

## Development

### AI Assistant Rules
This project includes opinionated rules files for AI coding assistants in `CLAUDE.md`. These establish:
- Modern SwiftUI patterns (no ViewModels)
- Swift 6 strict concurrency compliance  
- iOS 18+ API usage preferences
- Swift Testing framework adoption

### Architecture Notes
- **Workspace + SPM**: Clean separation between app shell and features
- **@Observable Pattern**: Modern state management without ViewModels
- **MainActor Isolation**: Proper concurrency for UI updates
- **File-based Configuration**: XCConfig and entitlements management

## Contributing

1. Follow the coding standards defined in `CLAUDE.md`
2. Ensure all tests pass with Swift Testing framework
3. Maintain Swift 6 concurrency compliance
4. Update documentation for new features

## License

[Add your chosen license here]

---

**Generated with [Claude Code](https://claude.ai/code)**