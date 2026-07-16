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

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart'
    show setupFirebaseCoreMocks;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:campusbite/firebase_options.dart';

/// Initializes Firebase with test-appropriate options and mocks the
/// Firebase Core and Auth platform channels so the app can start without a
/// native platform connection.
///
/// Call this in `setUpAll()` before any widget test that depends on
/// `MyApp`, the router, or any Firebase service.
Future<void> setupFirebaseForTest() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock SharedPreferences so AuthService doesn't crash on register/login.
  SharedPreferences.setMockInitialValues({});

  // ── 1. Mock Firebase Core Pigeon channels ───────────────────────────
  // The firebase_core_platform_interface package provides
  // setupFirebaseCoreMocks() which registers a MockFirebaseApp that
  // returns valid dummy values for initializeApp, initializeCore, and
  // optionsFromResource.  This MUST be called BEFORE
  // Firebase.initializeApp(), because that method internally calls the
  // FirebaseCoreHostApi Pigeon methods.
  setupFirebaseCoreMocks();

  // ── 2. Initialise Firebase Core ─────────────────────────────────────
  // The test runner defaults to TargetPlatform.android, so the Android
  // FirebaseOptions defined in firebase_options.dart are used.
  //
  // setupFirebaseCoreMocks() above already registers a MockFirebaseApp
  // whose initializeCore returns a pre-loaded [DEFAULT] app, so if an
  // exception fires here (duplicate-app) it's safe to ignore — Firebase
  // is already usable through the mock.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // App already exists in the mock — no action needed.
  }

  // ── 3. Mock the Pigeon BasicMessageChannels used by Firebase Auth ────
  // During initialisation FirebaseAuth internally calls two Pigeon
  // methods to register auth-state and id-token listeners.  Each returns
  // an EventChannel name (a plain String).
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const String authStateChannel =
      'dev.flutter.pigeon.firebase_auth_platform_interface'
      '.FirebaseAuthHostApi.registerAuthStateListener';

  const String idTokenChannel =
      'dev.flutter.pigeon.firebase_auth_platform_interface'
      '.FirebaseAuthHostApi.registerIdTokenListener';

  // Return synthetic event-channel names so the registration succeeds.
  const String fakeAuthStateEventChannel = 'test_auth_state_events';
  const String fakeIdTokenEventChannel = 'test_id_token_events';

  for (final entry in {
    authStateChannel: fakeAuthStateEventChannel,
    idTokenChannel: fakeIdTokenEventChannel,
  }.entries) {
    messenger.setMockMessageHandler(entry.key, (ByteData? _) async {
      return StandardMessageCodec().encodeMessage([entry.value]);
    });
  }

  // Mock the EventChannels that Firebase Auth listens on.
  // EventChannel internally uses MethodChannel which calls
  // `binaryMessenger.send()` then decodes the response.  Return a
  // valid success envelope with null data so the MethodChannel
  // decodes it as "success with null result" instead of throwing
  // MissingPluginException.
  for (final channelName in {
    fakeAuthStateEventChannel,
    fakeIdTokenEventChannel,
  }) {
    messenger.setMockMessageHandler(
      channelName,
      (_) async => StandardMethodCodec().encodeSuccessEnvelope(null),
    );
  }
}
