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
import 'package:campusbite/services/connectivity_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectivityService Tests', () {
    test('initial state defaults to online', () {
      final service = ConnectivityService.testing(initialOnline: true);
      expect(service.isOnline, isTrue);
    });

    test('initial state respects initialOnline false', () {
      final service = ConnectivityService.testing(initialOnline: false);
      expect(service.isOnline, isFalse);
    });

    test('setOnline updates state and emits on stream', () async {
      final service = ConnectivityService.testing(initialOnline: true);
      final events = <bool>[];
      final sub = service.onConnectivityChanged.listen(events.add);

      service.setOnline(false);
      service.setOnline(false); // duplicate should not re-emit
      service.setOnline(true);

      await Future.delayed(Duration.zero);
      expect(events, equals([false, true]));
      expect(service.isOnline, isTrue);
      await sub.cancel();
    });

    test('listens to injected stream in testing constructor', () async {
      final controller = StreamController<bool>();
      final service = ConnectivityService.testing(
        initialOnline: true,
        connectivityStream: controller.stream,
      );

      expect(service.isOnline, isTrue);

      controller.add(false);
      await Future.delayed(Duration.zero);
      expect(service.isOnline, isFalse);

      controller.add(true);
      await Future.delayed(Duration.zero);
      expect(service.isOnline, isTrue);

      await controller.close();
    });
  });
}
