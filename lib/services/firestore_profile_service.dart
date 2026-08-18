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

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_profile.dart';

/// Service that handles Firestore user profile reads and writes.
///
/// All writes go through Firestore security rules which enforce:
/// - Students may only update their own profile (isOwner check)
/// - Students may update: fullName, email (with email == auth token email),
///   phoneNumber, cafeName
/// - Students may NOT update: pickupReliability, role, strikeCount, etc.
/// - Admins may never update student profile info (name, email, etc.)
/// - Admins may only update strike-related fields via validAdminStrikeUpdate()
class FirestoreProfileService {
  final FirebaseFirestore _firestore;

  FirestoreProfileService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Updates the current user's profile name and/or email.
  ///
  /// The Firestore security rules validate:
  /// - isOwner: caller must match the userId being updated
  /// - studentNotModifyingProtectedFields: only allowed fields may change
  /// - email must match request.auth.token.email
  /// - length and format validations
  Future<void> updateProfile({
    required String userId,
    required String fullName,
    required String email,
  }) async {
    final docRef = _firestore.collection('users').doc(userId);
    try {
      await docRef.update({
        'fullName': fullName,
        'email': email,
        // Server-authoritative timestamp; the rules accept it only when it
        // equals request.time (the server timestamp sentinel).
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      // A missing user document (never-created or legacy profile) cannot be
      // updated. Recheck inside a transaction so a document created by another
      // writer between the failed update and this retry is preserved: only a
      // still-absent document is created (with the full student shape required
      // by validUserCreateRequest), and an existing one is partially updated —
      // never overwritten with toFirestoreCreate defaults that could clobber
      // server-authoritative fields (pickupReliability, accountStatus, ...).
      if (e.code != 'not-found') rethrow;
      await _firestore.runTransaction((txn) async {
        final snapshot = await txn.get(docRef);
        if (snapshot.exists) {
          txn.update(docRef, {
            'fullName': fullName,
            'email': email,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          txn.set(
            docRef,
            UserProfile(fullName: fullName, email: email).toFirestoreCreate(),
          );
        }
      });
    }
  }
}