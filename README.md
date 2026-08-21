# BloraLauncher

BloraLauncher is a high-performance, cross-platform Minecraft launcher designed for stability and speed. It provides a seamless experience for managing Minecraft versions, installing loaders, and optimizing game performance across Windows, macOS, and Linux.

## Overview

BloraLauncher leverages modern technologies including Git-based repository cloning and multithreaded downloads to deliver rapid installation times while maintaining file integrity. Built with Flutter, it offers a responsive and intuitive user interface across all supported platforms.

## Core Features

- Fast Installation: Utilizes Git-based repository cloning for rapid Minecraft version deployment, significantly reducing installation time compared to traditional download methods.
- Loader Support: Native support for Forge, NeoForge, and Fabric installation, enabling compatibility with a comprehensive range of community mods.
- Dynamic Runtime Management: Intelligent detection and automatic completion of runtime dependencies, including native libraries and game assets.
- Modern User Interface: Built with Flutter for a responsive and smooth user experience across all supported platforms.
- Version Integrity: Automated verification system using SHA1 checksums to ensure game files remain valid and consistent.
- Cross-Platform Compatibility: Seamless operation on Windows, macOS, and Linux systems.

## Technology Stack

- Frontend: Dart with Flutter framework
- Native Components: C++ for performance-critical operations
- Build System: CMake for cross-platform compilation
- Kotlin and Swift: Platform-specific implementations for Android and iOS support

## Getting Started

### Prerequisites

- Flutter SDK (latest stable version)
- Java 8 or higher (required for installing mod loaders)
- Git (required for repository cloning functionality)
- CMake (for building native components)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/BloretCrew/BloraLauncher.git
   cd BloraLauncher
   ```

2. Install Flutter dependencies:
   ```bash
   flutter pub get
   ```

3. Build native components:
   ```bash
   cmake -B build
   cmake --build build
   ```

4. Run the application:
   ```bash
   flutter run
   ```

### Build for Production

To create a production build for your target platform:

- Windows:
  ```bash
  flutter build windows
  ```

- macOS:
  ```bash
  flutter build macos
  ```

- Linux:
  ```bash
  flutter build linux
  ```

## Architecture

The application follows a modular architecture with clearly separated concerns:

- DownloadService: Manages file lifecycle including multithreaded downloads, SHA1-based integrity verification, and automated extraction of native libraries.
- GitService: Handles repository-based version deployment using Git protocols for efficient version management and updates.
- InstallManager: Coordinates the multistep installation process including JSON metadata merging, runtime environment configuration, and dependency resolution.
- RuntimeManager: Detects and completes runtime dependencies ensuring all required components are available before game launch.

## Project Structure

```
BloraLauncher/
├── lib/
│   ├── services/
│   ├── ui/
│   ├── models/
│   └── main.dart
├── windows/
├── macos/
├── linux/
├── ios/
├── android/
├── cpp/
├── CMakeLists.txt
├── pubspec.yaml
└── README.md
```

## Contributing

Contributions are welcome. To contribute to BloraLauncher:

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a pull request

Please ensure all code follows the project's coding standards and include appropriate tests with your submissions.

## License

This project is licensed under the MIT License. See the LICENSE file for detailed information.

## Support

For issues, feature requests, or contributions, please use the following resources:

- Open an issue on the repository issue tracker
- Consult the official documentation
- Review existing issues for solutions to common problems

## Acknowledgments

BloraLauncher builds upon the excellent work of the Minecraft modding community and leverages established frameworks and tools in the ecosystem.
