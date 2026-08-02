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

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_test/flutter_test.dart';

import 'package:campusbite/services/auth_service.dart';
import 'package:campusbite/services/email_verification_service.dart';
import 'package:campusbite/viewmodels/verify_email_view_model.dart';

import 'firebase_test_helper.dart';

/// [AuthService] whose async operations can be held open by the test until
/// resolved, so a ViewModel can be disposed while work is pending.
class _HeldAuthService extends AuthService {
  _HeldAuthService({this.user});
  final User? user;

  final Completer<String?> reloadCompleter = Completer<String?>();
  final Completer<String?> refreshCompleter = Completer<String?>();
  final Completer<String?> sendCompleter = Completer<String?>();

  bool emailVerified = true;

  /// Set to `true` when [reloadUser] is actually invoked by the ViewModel.
  bool reloadUserCalled = false;

  /// Set to `true` when [sendVerificationEmail] is actually invoked.
  bool sendVerificationEmailCalled = false;

  @override
  User? get currentUser => user;

  @override
  bool get isEmailVerified => emailVerified;

  @override
  Future<String?> reloadUser() {
    reloadUserCalled = true;
    return reloadCompleter.future;
  }

  @override
  Future<String?> refreshIdToken() => refreshCompleter.future;

  @override
  Future<String?> sendVerificationEmail() {
    sendVerificationEmailCalled = true;
    return sendCompleter.future;
  }
}

/// [EmailVerificationService] whose profile creation can be held pending.
class _HeldVerificationService extends EmailVerificationService {
  final Completer<String?> profileCompleter = Completer<String?>();

  @override
  Future<String?> createProfileAfterVerification(User user) =>
      profileCompleter.future;
}

void main() {
  setUpAll(setupFirebaseForTest);

  group('VerifyEmailViewModel dispose safety', () {
    test('verify() does not notify a disposed notifier after reload', () async {
      final auth = _HeldAuthService(user: null);
      final verification = _HeldVerificationService();
      final vm = VerifyEmailViewModel(
        authService: auth,
        verificationService: verification,
      );

      final future = vm.verify();
      // The reload must actually be in flight before we dispose — guards
      // against passing by completing a never-used Completer.
      expect(auth.reloadUserCalled, isTrue);
      // Reload is pending; the ViewModel is disposed mid-flight.
      vm.dispose();
      auth.reloadCompleter.complete(null);

      // Settling after dispose must not throw.
      await expectLater(future, completes);
    });

    test('verify() completing after dispose does not throw (verified path)',
        () async {
      final auth = _HeldAuthService(user: null);
      final verification = _HeldVerificationService();
      final vm = VerifyEmailViewModel(
        authService: auth,
        verificationService: verification,
      );

      final future = vm.verify();
      expect(auth.reloadUserCalled, isTrue);
      vm.dispose();
      auth.reloadCompleter.complete(null);

      // isVerified branch runs without a listener and calls _setLoading/_setMessage
      // after dispose — these must be no-ops, not exceptions.
      await expectLater(future, completes);
    });

    test('resend() completing after a dispose does not throw', () async {
      final auth = _HeldAuthService(user: null);
      final verification = _HeldVerificationService();
      final vm = VerifyEmailViewModel(
        authService: auth,
        verificationService: verification,
      );

      final future = vm.resend();
      // The send must actually be in flight before dispose.
      expect(auth.sendVerificationEmailCalled, isTrue);
      // resend starts immediately (canResend is true), is pending on send.
      vm.dispose();
      auth.sendCompleter.complete(null);

      await expectLater(future, completes);
    });
  });
}