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
import 'package:campusbite/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Notifies go_router whenever Firebase auth state changes, so it can
/// re-evaluate redirects.
class AuthNotifier extends ChangeNotifier {
  AuthNotifier() {
    _subscription = AuthService().authStateChanges.listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<User?> _subscription;

  /// The currently signed-in Firebase user (or null).
  ///
  /// Phase 13: simplified from a broken `isBroadcast` check that always
  /// returned null — this getter now returns the live auth user directly.
  User? get currentUser => FirebaseAuth.instance.currentUser;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
