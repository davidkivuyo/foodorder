// Copyright 2026 davidkivuyo, johnsonmushi, edwinkessy276-art, jugraki-art.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// Platform seam for the in-app update system.
///
/// The app also builds for web, where `dart:io` and the update platform
/// channels are unavailable. `update_platform.dart` conditionally exports the
/// real Android implementation on native builds and this no-op stub on web.
library;

/// A handle over an open, writable file used while streaming a download.
/// Avoids leaking `dart:io` types into the service layer.
abstract class UpdateFileHandle {
  Future<void> write(List<int> bytes);
  Future<void> close();
}

/// Operations the update flow needs that differ per platform.
abstract class UpdatePlatform {
  /// Whether in-app APK updates are supported on this platform (Android only).
  bool get supported;

  /// Device ABI, e.g. `arm64-v8a`; `null` when unknown.
  Future<String?> deviceAbi();

  /// Whether the OS allows installing packages from this app (Android 8+).
  Future<bool> canRequestPackageInstalls();

  /// Opens the "Install unknown apps" settings screen.
  Future<void> openInstallSettings();

  /// Launches the system package installer for the APK at [apkPath].
  /// Returns true when the installer activity was started.
  Future<bool> launchInstaller(String apkPath);

  /// Opens [path] for writing; when [append] is true bytes are appended.
  Future<UpdateFileHandle?> openFile(String path, {required bool append});

  Future<void> deleteFile(String path);
  Future<bool> fileExists(String path);
  Future<int> fileLength(String path);

  /// Renames [from] to [to]; false on failure.
  Future<bool> renameFile(String from, String to);

  /// Lists the file names inside [dir]; empty list on failure.
  Future<List<String>> listDirectory(String dir);

  /// Lowercase hex SHA-256 of the file at [path].
  Future<String> fileSha256(String path);

  /// Path to the app-private directory used to stage installers.
  Future<String> updatesDirectory();
}

/// Default no-op implementation used on unsupported platforms (web).
class UnsupportedUpdatePlatform implements UpdatePlatform {
  @override
  bool get supported => false;

  @override
  Future<String?> deviceAbi() async => null;

  @override
  Future<bool> canRequestPackageInstalls() async => false;

  @override
  Future<void> openInstallSettings() async {}

  @override
  Future<bool> launchInstaller(String apkPath) async => false;

  @override
  Future<UpdateFileHandle?> openFile(String path, {required bool append}) async =>
      null;

  @override
  Future<void> deleteFile(String path) async {}

  @override
  Future<bool> fileExists(String path) async => false;

  @override
  Future<int> fileLength(String path) async => 0;

  @override
  Future<bool> renameFile(String from, String to) async => false;

  @override
  Future<List<String>> listDirectory(String dir) async => const [];

  @override
  Future<String> fileSha256(String path) async => '';

  @override
  Future<String> updatesDirectory() async => '';
}

/// Concrete [UpdatePlatform] for the current platform.
UpdatePlatform get updatePlatform => UnsupportedUpdatePlatform();
