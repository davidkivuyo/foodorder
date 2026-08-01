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

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'update_platform_stub.dart'
    hide UnsupportedUpdatePlatform, updatePlatform;

export 'update_platform_stub.dart' show UpdatePlatform, UpdateFileHandle;

/// Android implementation backed by the native MethodChannel and `dart:io`.
class AndroidUpdatePlatform implements UpdatePlatform {
  static const MethodChannel _channel = MethodChannel('campusbite/update');

  @override
  bool get supported => Platform.isAndroid;

  @override
  Future<String?> deviceAbi() async {
    try {
      final abi = await _channel.invokeMethod<String>('getDeviceAbi');
      if (abi == null || abi.isEmpty || abi == 'unknown') return null;
      return abi;
    } on MissingPluginException {
      return null;
    } on Exception catch (_) {
      return null;
    }
  }

  @override
  Future<bool> canRequestPackageInstalls() async {
    if (!Platform.isAndroid) return false;
    try {
      // Only an explicit `true` from the native side grants permission. A null
      // result or any channel failure means the state was never confirmed.
      return await _channel.invokeMethod<bool>('canRequestPackageInstalls') ??
          false;
    } on MissingPluginException {
      return false;
    } on Exception catch (_) {
      return false;
    }
  }

  @override
  Future<void> openInstallSettings() async {
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } on Exception catch (_) {
      // Best effort — the user can also enable it in system settings.
    }
  }

  @override
  Future<bool> launchInstaller(String apkPath) async {
    try {
      await _channel.invokeMethod<void>('installApk', {'path': apkPath});
      return true;
    } on PlatformException {
      // The native side reports a failed launch (e.g. no installer activity
      // resolved) as an error.
      return false;
    } on MissingPluginException {
      return false;
    } on Exception catch (_) {
      return false;
    }
  }

  @override
  Future<UpdateFileHandle?> openFile(String path, {required bool append}) async {
    try {
      final raf = await File(path)
          .open(mode: append ? FileMode.append : FileMode.write);
      return _IoUpdateFileHandle(raf);
    } on Exception catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } on Exception catch (_) {
      // Best effort cleanup.
    }
  }

  @override
  Future<bool> fileExists(String path) async {
    try {
      return await File(path).exists();
    } on Exception catch (_) {
      return false;
    }
  }

  @override
  Future<int> fileLength(String path) async {
    try {
      return await File(path).length();
    } on Exception catch (_) {
      return 0;
    }
  }

  @override
  Future<bool> renameFile(String from, String to) async {
    try {
      final f = File(from);
      if (!await f.exists()) return false;
      await f.rename(to);
      return true;
    } on Exception catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> listDirectory(String dir) async {
    try {
      final d = Directory(dir);
      if (!await d.exists()) return const [];
      return d
          .listSync()
          .map((e) => e.path.split('/').last)
          .toList(growable: false);
    } on Exception catch (_) {
      return const [];
    }
  }

  @override
  Future<String> fileSha256(String path) async {
    try {
      final digest = await sha256.bind(File(path).openRead()).first;
      return digest.toString();
    } on Exception catch (_) {
      return '';
    }
  }

  @override
  Future<String> updatesDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory('${supportDir.path}/updates');
    await dir.create(recursive: true);
    return dir.path;
  }
}

class _IoUpdateFileHandle implements UpdateFileHandle {
  _IoUpdateFileHandle(this._raf);

  final RandomAccessFile _raf;

  @override
  Future<void> write(List<int> bytes) async {
    await _raf.writeFrom(bytes);
  }

  @override
  Future<void> close() async {
    try {
      await _raf.flush();
    } finally {
      await _raf.close();
    }
  }
}

/// Concrete [UpdatePlatform] for native Android builds.
UpdatePlatform get updatePlatform => AndroidUpdatePlatform();
