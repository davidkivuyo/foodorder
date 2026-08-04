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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/update_info.dart';
import 'app_log.dart';
import 'http_headers.dart';
import 'update_platform.dart';
import 'version_comparator.dart';

/// Lifecycle of the in-app update flow.
enum UpdateState {
  /// Nothing has been decided yet.
  idle,

  /// Checking the endpoint for a newer version.
  checking,

  /// App is current — no update offered.
  current,

  /// Optional update available (dismissible).
  updateAvailable,

  /// Mandatory update — app usage is blocked until updated.
  updateRequired,

  /// Download in progress.
  downloading,

  /// Download paused; can be resumed.
  paused,

  /// Verifying the SHA-256 checksum of the downloaded installer.
  verifying,

  /// Installer verified — ready to launch the installer.
  readyToInstall,

  /// Installer permission missing; open settings to enable it.
  installPermissionRequired,

  /// Installer launched.
  installing,

  /// Update completed.
  installed,

  /// Last action failed (download / verify / install).
  failed,
}

/// Single source of truth for the in-app update flow.
///
/// Rules enforced here:
/// - Only `https://dl.larason.space/...` download URLs are accepted.
/// - Check results are cached locally with an independent TTL so the endpoint
///   is never called more than once per cache-validity window.
/// - Every network failure in the check path is silently swallowed (debug-log
///   only) and the app keeps running on the current version.
/// - Full download URLs are never logged.
class UpdateService extends ChangeNotifier {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  /// The ONLY host the app is allowed to download from.
  static const String allowedHost = 'dl.larason.space';

  /// Local cache TTL, independent of the Worker's 5-minute edge TTL.
  static const Duration localCacheTtl = Duration(hours: 12);

  static const String _cacheKey = 'update_metadata_cache';
  static const String _cacheTimeKey = 'update_metadata_cached_at';
  static const String _dismissedKey = 'update_dismissed_version';

  static const List<String> supportedAbis = [
    'arm64-v8a',
    'armeabi-v7a',
    'x86_64',
  ];

  static const int maxRetries = 3;

  /// Upper bound on redirect hops followed (each validated against
  /// [allowedHost]) before a download/checksum fetch is abandoned.
  static const int maxRedirects = 3;

  UpdateState _state = UpdateState.idle;
  UpdateInfo? _info;
  String? _errorMessage;
  bool _errorRetryable = false;
  bool _dismissed = false;
  bool _busy = false;

  // Download progress state.
  double _progress = 0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  Duration _eta = Duration.zero;
  bool _paused = false;
  String? _installerPath;
  http.StreamedResponse? _streamedResponse;
  StreamSubscription<List<int>>? _downloadSub;
  UpdateFileHandle? _fileHandle;
  http.Client? _downloadClient;
  int _retryCount = 0;
  String? _abi;

  UpdateState get state => _state;
  UpdateInfo? get info => _info;
  String? get errorMessage => _errorMessage;
  bool get errorRetryable => _errorRetryable;
  double get progress => _progress;
  int get receivedBytes => _receivedBytes;
  int get totalBytes => _totalBytes;
  Duration get eta => _eta;
  bool get isPaused => _paused;
  String? get installerPath => _installerPath;

  bool get hasUpdate =>
      _state == UpdateState.updateAvailable ||
      _state == UpdateState.updateRequired;

  bool get isMandatory => _state == UpdateState.updateRequired;

  bool get dismissed => _dismissed;

  void _setState(UpdateState state) {
    _state = state;
    notifyListeners();
  }

  // ── Update check ────────────────────────────────────────────────────────

  /// Checks for an update, respecting the local cache TTL. Every network
  /// failure is swallowed (debug-log only) so the app continues normally.
  Future<void> checkForUpdate() async {
    if (_busy) return;
    if (!updatePlatform.supported) return;

    _busy = true;
    _setState(UpdateState.checking);
    try {
      final cached = await _readCachedInfo();
      if (cached != null) {
        await _applyInfo(cached);
        return;
      }

      final fetched = await _fetchLatest();
      if (fetched == null) {
        // Network failure or non-200 — silently fall back to whatever is
        // cached (even if stale) or stay on the current version.
        final fallback = await _readRawCache();
        if (fallback != null) {
          await _applyInfo(fallback);
        } else {
          await _cleanupSupersededInstallers();
          _setState(UpdateState.current);
        }
        return;
      }

      await _writeCache(fetched);
      await _applyInfo(fetched);
    } on Exception catch (e, stack) {
      AppLog.e('[Update] check failed', e, stack);
      await _cleanupSupersededInstallers();
      _setState(UpdateState.current);
    } finally {
      _busy = false;
    }
  }

  Future<UpdateInfo?> _fetchLatest() async {
    final uri = Uri.https(allowedHost, '/latest');
    final res = await http
        .get(uri, headers: {HttpHeaders.acceptHeader: 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      AppLog.w('[Update] check returned HTTP ${res.statusCode}');
      return null;
    }
    final json = _decodeJson(res.body);
    if (json == null) return null;
    return UpdateInfo.fromJson(json);
  }

  Future<UpdateInfo?> _readCachedInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedAt = prefs.getInt(_cacheTimeKey);
    if (cachedAt == null) return null;
    final age =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(cachedAt));
    if (age > localCacheTtl) return null;
    return _readRawCache();
  }

  Future<UpdateInfo?> _readRawCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return null;
    final json = _decodeJson(raw);
    if (json == null) return null;
    return UpdateInfo.fromJson(json);
  }

  Future<void> _writeCache(UpdateInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(info.toJson()));
    await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _applyInfo(UpdateInfo info) async {
    _info = info;

    final pkg = await PackageInfo.fromPlatform();
    final current = pkg.version;

    final decision = decideState(
      current: current,
      remoteVersion: info.version,
      minimumVersion: info.minimumVersion,
      forceUpdate: info.forceUpdate,
    );
    AppLog.d('[Update] local=$current remote=${info.version} '
        'minimum=${info.minimumVersion} forceUpdate=${info.forceUpdate} → '
        '$decision');

    if (decision == UpdateState.updateRequired) {
      _setState(UpdateState.updateRequired);
      return;
    }

    if (decision == UpdateState.updateAvailable) {
      final dismissedVersion = await _readDismissedVersion();
      _dismissed = dismissedVersion == info.version;
      if (_dismissed) {
        _setState(UpdateState.current);
      } else {
        _setState(UpdateState.updateAvailable);
      }
      return;
    }

    // Running version is current (or newer) — any downloaded installer is
    // superseded. Storage hygiene: drop it and any leftover `.part` files.
    await _cleanupSupersededInstallers();
    _setState(UpdateState.current);
  }

  /// Decides the base update state for [current] against the remote metadata.
  ///
  /// This is the only place in the app that turns version strings into an
  /// update decision. It uses [VersionComparator] (semver-aware) and treats a
  /// malformed version as fail-safe-neutral — same as an update-check network
  /// failure: continue on the current version, debug-log only, never throw.
  /// The optional-update dismissal and installer cleanup that branch off this
  /// base decision live in [_applyInfo].
  @visibleForTesting
  static UpdateState decideState({
    required String current,
    required String remoteVersion,
    required String minimumVersion,
    required bool forceUpdate,
  }) {
    try {
      final isBelowMinimum = VersionComparator.isBelowMinimum(
        local: current,
        minimum: minimumVersion,
      );
      final isNewer = VersionComparator.isNewer(
        local: current,
        remote: remoteVersion,
      );

      if (forceUpdate || isBelowMinimum) return UpdateState.updateRequired;
      if (isNewer) return UpdateState.updateAvailable;
      return UpdateState.current;
    } on VersionParseException catch (e) {
      AppLog.d('[Update] unparseable version metadata — staying on current '
          'version (${e.runtimeType})');
      return UpdateState.current;
    }
  }

  Future<String?> _readDismissedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_dismissedKey);
  }

  /// Dismisses the optional prompt for this version.
  Future<void> dismiss() async {
    if (_info == null) return;
    // Mandatory updates can never be dismissed — no state, persistence, or
    // flag changes, even if the widget layer misbehaves.
    if (_state == UpdateState.updateRequired) return;
    _dismissed = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedKey, _info!.version);
    _setState(UpdateState.current);
  }

  // ── Download ────────────────────────────────────────────────────────────

  /// Starts (or resumes) the download for the matching ABI.
  Future<void> startDownload() async {
    if (_state != UpdateState.updateAvailable &&
        _state != UpdateState.updateRequired &&
        _state != UpdateState.paused &&
        _state != UpdateState.failed) {
      return;
    }

    if (_state == UpdateState.paused) {
      await _resumeDownload();
      return;
    }

    final info = _info;
    if (info == null) {
      _fail('Update unavailable.');
      return;
    }

    _abi = await updatePlatform.deviceAbi();
    final url = _pickDownloadUrl(info);
    if (url == null) {
      _fail('Update unavailable for this device.');
      return;
    }

    _retryCount = 0;
    await _downloadTo(info, url);
  }

  Future<void> _resumeDownload() async {
    final info = _info;
    if (info == null) {
      _fail('Update unavailable.');
      return;
    }
    final url = _pickDownloadUrl(info);
    if (url == null) {
      _fail('Update unavailable for this device.');
      return;
    }
    final target = _installerPath ?? await _buildTargetPath(info);
    if (target == null) {
      _fail('Update unavailable for this device.');
      return;
    }
    _installerPath = target;
    await _downloadTo(info, url);
  }

  /// Builds the staging path for the installer. Returns null when no
  /// compatible ABI is available for this device.
  Future<String?> _buildTargetPath(UpdateInfo info) async {
    final key = _abiKey(info);
    if (key == null) return null;
    final filename = _safeFilename(info.version, key);
    final dir = await updatePlatform.updatesDirectory();
    return '$dir/$filename';
  }

  /// Selects the download URL for the device ABI (universal fallback).
  String? _pickDownloadUrl(UpdateInfo info) {
    final key = _abiKey(info);
    final url = info.downloads[key];
    if (url == null || !_isAllowedUrl(url)) {
      AppLog.w('[Update] rejecting disallowed download URL');
      return null;
    }
    return url;
  }

  String? _pickChecksumUrl(UpdateInfo info) {
    final key = _abiKey(info);
    final url = info.checksums[key];
    if (url == null || !_isAllowedUrl(url)) {
      AppLog.w('[Update] rejecting disallowed checksum URL');
      return null;
    }
    return url;
  }

  /// Selects the download key for this device: the detected ABI when present,
  /// else `universal`. Returns null when neither is available so unresolved
  /// devices fail instead of picking an arbitrary incompatible installer.
  String? _abiKey(UpdateInfo info) {
    final abi = _abi;
    if (abi != null && info.downloads.containsKey(abi)) return abi;
    if (info.downloads.containsKey('universal')) return 'universal';
    return null;
  }

  Future<void> _downloadTo(UpdateInfo info, String url) async {
    _setState(UpdateState.downloading);
    _paused = false;
    _errorMessage = null;
    _errorRetryable = false;

    // A retry re-enters here while a previous attempt's client may still be
    // alive — drop it before creating the next one.
    _closeDownloadClient();

    final target = _installerPath ?? await _buildTargetPath(info);
    if (target == null) {
      _fail('Update unavailable for this device.');
      return;
    }
    _installerPath = target;

    await _cleanupOldInstallers(target);

    final partPath = '$target.part';
    var startOffset = await updatePlatform.fileLength(partPath);

    try {
      final request = http.Request('GET', Uri.parse(url))
        ..followRedirects = false;
      if (startOffset > 0) {
        request.headers[HttpHeaders.rangeHeader] = 'bytes=$startOffset-';
      }
      final client = http.Client();
      _downloadClient = client;
      _streamedResponse = await _sendNoRedirect(client, request, url);
      if (_streamedResponse == null) {
        _closeDownloadClient();
        _fail('Could not start download.');
        return;
      }

      final status = _streamedResponse!.statusCode;
      if (status != 200 && status != 206) {
        _closeDownloadClient();
        _fail('Could not start download ($status).');
        return;
      }

      if (status == 200 && startOffset > 0) {
        // Server ignored the Range header — restart from scratch. Reset the
        // offset so the progress/speed math below counts only fresh bytes.
        await updatePlatform.deleteFile(partPath);
        startOffset = 0;
      }

      final contentLength = int.tryParse(
        _streamedResponse!.headers[HttpHeaders.contentLengthHeader] ?? '',
      ) ?? -1;
      final resumed = status == 206 && startOffset > 0;
      _totalBytes = contentLength < 0
          ? 0
          : (resumed ? startOffset + contentLength : contentLength);
      _receivedBytes = startOffset;

      final append = resumed;
      _fileHandle = await updatePlatform.openFile(partPath, append: append);
      if (_fileHandle == null) {
        _closeDownloadClient();
        _fail('Could not open download file.');
        return;
      }

      final stopwatch = Stopwatch()..start();
      var lastReceived = startOffset;

      _downloadSub = _streamedResponse!.stream.listen(
        (chunk) async {
          // Pause the stream so the next chunk can only be delivered after
          // this write and its progress updates finish. Stream.listen does
          // not await async onData callbacks, so without this, overlapping
          // writes could interleave on the same file handle.
          _downloadSub?.pause();
          await _fileHandle?.write(chunk);
          lastReceived += chunk.length;
          _receivedBytes = lastReceived;
          final elapsedSec =
              (stopwatch.elapsedMilliseconds / 1000).clamp(0.001, 1e9);
          final speed = (lastReceived - startOffset) / elapsedSec;
          final remaining = _totalBytes > 0
              ? (_totalBytes - lastReceived).clamp(0, _totalBytes)
              : 0;
          _eta = speed > 0
              ? Duration(seconds: (remaining / speed).round())
              : Duration.zero;
          _progress = _totalBytes > 0
              ? (lastReceived / _totalBytes).clamp(0.0, 1.0)
              : 0;
          notifyListeners();
          _downloadSub?.resume();
        },
        onError: (Object e) async {
          _downloadSub?.cancel();
          await _closeFile();
          if (!_paused && _retryCount < maxRetries) {
            _retryCount++;
            AppLog.d('[Update] download attempt $_retryCount failed, retrying');
            await Future<void>.delayed(const Duration(seconds: 2));
            if (!_paused) {
              await _downloadTo(info, url);
            } else {
              _closeDownloadClient();
              _setState(UpdateState.paused);
            }
          } else {
            _closeDownloadClient();
            _fail('Download failed.');
          }
        },
        onDone: () async {
          _closeDownloadClient();
          await _closeFile();
          if (_paused) return;
          final ok = await updatePlatform.renameFile(partPath, target);
          if (!ok) {
            _fail('Could not finalize download.');
            return;
          }
          await _verifyAndInstall(info);
        },
      );
    } on Exception catch (e) {
      _closeDownloadClient();
      AppLog.d('[Update] download threw: ${e.runtimeType}');
      if (!_paused && _retryCount < maxRetries) {
        _retryCount++;
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!_paused) {
          await _downloadTo(info, url);
        } else {
          _setState(UpdateState.paused);
        }
      } else {
        _fail('Download failed.');
      }
    }
  }

  Future<void> _verifyAndInstall(UpdateInfo info) async {
    _setState(UpdateState.verifying);
    final path = _installerPath;
    if (path == null) {
      _fail('Update unavailable.');
      return;
    }

    final checksumUrl = _pickChecksumUrl(info);
    if (checksumUrl == null) {
      // No checksum to compare — fail closed rather than install unverified.
      await updatePlatform.deleteFile(path);
      _fail('Could not verify the update.');
      return;
    }

    try {
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(checksumUrl))
          ..followRedirects = false;
        final response = await _sendNoRedirect(client, request, checksumUrl);
        if (response == null) {
          await updatePlatform.deleteFile(path);
          _fail('Could not verify the update.');
          return;
        }
        final res = await http.Response.fromStream(response).timeout(
              const Duration(seconds: 15),
            );
        if (res.statusCode != 200) {
          await updatePlatform.deleteFile(path);
          _fail('Could not verify the update.');
          return;
        }
        final expected = _parseChecksum(res.body);
        final actual = await updatePlatform.fileSha256(path);
        if (expected == null ||
            expected.isEmpty ||
            actual.isEmpty ||
            expected != actual) {
          AppLog.w('[Update] checksum mismatch — installer discarded');
          await updatePlatform.deleteFile(path);
          _fail('Could not verify the update.');
          return;
        }
      } finally {
        // Always release the checksum client — on success, validation
        // failures, and exceptions alike.
        client.close();
      }
    } on Exception catch (_) {
      await updatePlatform.deleteFile(path);
      _fail('Could not verify the update.');
      return;
    }

    _setState(UpdateState.readyToInstall);
  }

  /// Pauses the active download; the `.part` file is kept for resume.
  Future<void> pause() async {
    if (_state != UpdateState.downloading) return;
    _paused = true;
    await _downloadSub?.cancel();
    await _closeFile();
    _closeDownloadClient();
    _setState(UpdateState.paused);
  }

  /// Retries after a retryable failure.
  Future<void> retry() async {
    if (_state != UpdateState.failed) return;
    final info = _info;
    if (info == null) {
      _fail('Update unavailable.');
      return;
    }
    final url = _pickDownloadUrl(info);
    if (url == null) {
      // No supported ABI download (or the URL failed host validation).
      // Fail immediately with the device-support message — do not pass an
      // empty URL into the downloader or spend a retry on it.
      _fail('Update unavailable for this device.');
      return;
    }
    _retryCount = 0;
    final target = await _buildTargetPath(info);
    if (target == null) {
      _fail('Update unavailable for this device.');
      return;
    }
    _installerPath = target;
    await _downloadTo(info, url);
  }

  // ── Install ─────────────────────────────────────────────────────────────

  Future<void> install() async {
    if (_state != UpdateState.readyToInstall) return;
    final path = _installerPath;
    if (path == null) {
      _fail('Update unavailable.');
      return;
    }

    final canInstall = await updatePlatform.canRequestPackageInstalls();
    if (!canInstall) {
      _setState(UpdateState.installPermissionRequired);
      return;
    }

    final launched = await updatePlatform.launchInstaller(path);
    if (!launched) {
      _fail('Could not launch the installer.');
      return;
    }

    _setState(UpdateState.installing);

    // The installer owns the file once ACTION_VIEW hands it off. Stay pinned
    // to `installing`; the APK (and any superseded installers) are removed at
    // the next startup/update-check once the running version is reported
    // current — the 10s race here would only delete files the installer may
    // still be reading.
  }

  /// Opens system settings to grant install permission.
  Future<void> openInstallSettings() async {
    await updatePlatform.openInstallSettings();
  }

  /// Called when the user returns from settings; re-checks permission.
  Future<void> refreshInstallPermission() async {
    final canInstall = await updatePlatform.canRequestPackageInstalls();
    if (canInstall && _state == UpdateState.installPermissionRequired) {
      _setState(UpdateState.readyToInstall);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  void _fail(String message) {
    _errorMessage = message;
    _errorRetryable = true;
    _setState(UpdateState.failed);
  }

  Future<void> _closeFile() async {
    final h = _fileHandle;
    _fileHandle = null;
    await h?.close();
  }

  /// Releases the per-attempt HTTP client. Safe to call repeatedly; the field
  /// is nulled so a retry can never close the next attempt's client.
  void _closeDownloadClient() {
    final client = _downloadClient;
    _downloadClient = null;
    client?.close();
  }

  Future<void> _cleanupOldInstallers(String target) async {
    // Storage hygiene: keep only the installer we're about to write; delete
    // any previously downloaded/superseded APK and part files.
    final dir = target.substring(0, target.lastIndexOf('/') + 1);
    final keep = target.split('/').last;
    final entries = await updatePlatform.listDirectory(dir);
    for (final e in entries) {
      if (e == keep || e == '$keep.part') continue;
      await updatePlatform.deleteFile('$dir$e');
    }
  }

  /// Deletes every downloaded installer and leftover `.part` file. Invoked
  /// when the running version is reported current so a previously downloaded
  /// APK — including one handed to the installer — never lingers on disk.
  Future<void> _cleanupSupersededInstallers() async {
    try {
      final dir = await updatePlatform.updatesDirectory();
      final entries = await updatePlatform.listDirectory(dir);
      for (final e in entries) {
        if (e.endsWith('.apk') || e.endsWith('.part')) {
          await updatePlatform.deleteFile('$dir/$e');
        }
      }
    } on Exception catch (_) {
      // Best-effort hygiene — never let cleanup break the update check.
    }
  }

  bool _isAllowedUrl(String url) {
    return isAllowedDownloadUrl(url);
  }

  /// Rejects any download/checksum URL that isn't an `https` URL on the
  /// hardcoded [allowedHost]. Exposed for tests.
  @visibleForTesting
  static bool isAllowedDownloadUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.scheme == 'https' && uri.host == allowedHost;
    } on Exception catch (_) {
      return false;
    }
  }

  /// Resolves a redirect [location] against the [currentUrl] hop it was
  /// received from, then requires the resolved absolute URL to pass
  /// [isAllowedDownloadUrl]. Returns the resolved URL, or `null` when it lands
  /// on a disallowed host/scheme. Exposed for tests.
  ///
  /// `Location` headers may be relative (e.g. `/v1.4.2/app.apk`), so they must
  /// be resolved before host validation — otherwise a legitimate relative
  /// redirect on the allowed host would be rejected.
  @visibleForTesting
  static String? resolveRedirect(String location, String currentUrl) {
    final resolved = Uri.parse(currentUrl).resolve(location).toString();
    return isAllowedDownloadUrl(resolved) ? resolved : null;
  }

  /// Sends [request], following redirects only when each hop resolves to an
  /// allowed `dl.larason.space` URL. Returns `null` on a disallowed hop.
  Future<http.StreamedResponse?> _sendNoRedirect(
    http.Client client,
    http.Request request,
    String initialUrl,
  ) async {
    var url = initialUrl;
    for (var hops = 0; hops <= maxRedirects; hops++) {
      final hopRequest = http.Request('GET', Uri.parse(url))
        ..followRedirects = false;
      hopRequest.headers.addAll(request.headers);
      final response =
          await client.send(hopRequest).timeout(const Duration(seconds: 30));
      final status = response.statusCode;
      if (status < 300 || status >= 400) return response;
      final location = response.headers[HttpHeaders.locationHeader];
      await response.stream.drain<void>();
      if (location == null) {
        AppLog.w('[Update] rejecting redirect without location');
        return null;
      }
      final resolved = resolveRedirect(location, url);
      if (resolved == null) {
        AppLog.w('[Update] rejecting disallowed redirect');
        return null;
      }
      url = resolved;
    }
    AppLog.w('[Update] too many redirect hops');
    return null;
  }

  Map<String, dynamic>? _decodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Exception catch (_) {
      return null;
    }
  }

  /// Safe filename: `CampusBite-<version>-<abi>.apk`.
  String _safeFilename(String version, String abiKey) {
    final safeVersion = version.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final safeAbi = abiKey.replaceAll(RegExp(r'[^\w.\-]'), '_');
    return 'CampusBite-$safeVersion-$safeAbi.apk';
  }

  String? _parseChecksum(String body) {
    final m = RegExp(r'^\s*([0-9a-fA-F]{64})\b', multiLine: true)
        .firstMatch(body);
    return m?.group(1)?.toLowerCase();
  }
}
