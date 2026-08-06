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

import 'logger_service.dart';

/// Compatibility facade over [LoggerService] (Phase 17 — Part 4).
///
/// Existing call sites keep using this class; new code should log through
/// [LoggerService] directly. All privacy guarantees (sanitization before
/// emission, exception runtimeType only) are enforced inside
/// [LoggerService].
class AppLog {
  AppLog._();

  /// Debug-level log — stripped from release builds.
  static void d(String message) => LoggerService.instance.debug(message);

  /// Info-level log — stripped from release builds.
  static void i(String message) => LoggerService.instance.info(message);

  /// Warning-level log — emitted in all build modes.
  static void w(String message) => LoggerService.instance.warning(message);

  /// Error-level log — emitted in all build modes. Only logs the exception
  /// [runtimeType], never the raw exception string.
  static void e(String message, [Object? error, StackTrace? stack]) =>
      LoggerService.instance.error(message, error, stack);

  /// Redacts known sensitive patterns (see [LoggerService.sanitize]).
  static String sanitize(String message) => LoggerService.sanitize(message);
}
