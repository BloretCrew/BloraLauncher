# BloraLauncher

BloraLauncher is a high-performance, cross-platform Minecraft launcher designed for stability and speed. It provides a seamless experience for managing Minecraft versions, installing loaders, and optimizing game performance.

## Core Features

- **Fast Installation**: Leverages Git-based repository cloning for rapid Minecraft version deployment, bypassing traditional slow download speeds.
- **Loader Support**: Native support for Forge, NeoForge, and Fabric installation, ensuring compatibility with a wide range of community mods.
- **Dynamic Runtime Management**: Intelligent detection and completion of runtime dependencies, including native libraries and assets.
- **Modern UI**: Built with Flutter for a responsive and smooth user experience across platforms.
- **Version Integrity**: Automated verification system to ensure game files remain valid and consistent.

## Getting Started

### Prerequisites

- Flutter SDK (latest stable version)
- Java 8 or higher (for installing mod loaders)
- Git (required for fast cloning feature)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/BloretCrew/BloretLauncher.git
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the application:
   ```bash
   flutter run
   ```

## Architecture

- **DownloadService**: Handles file lifecycle, including multithreaded downloads, integrity verification (SHA1), and native library extraction.
- **GitService**: Manages repository-based version deployment using Git protocols.
- **InstallManager**: Coordinates the multistep installation process, including JSON metadata merging and runtime environment setup.

## License

This project is licensed under the MIT License. See the LICENSE file for details.

## Support

For issues, feature requests, or contributions, please open an issue in the repository or consult the official documentation.
