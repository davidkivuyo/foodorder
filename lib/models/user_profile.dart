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

/// Represents a student user profile stored under `users/{uid}`.
///
/// Encapsulates Firestore serialization so schema errors are caught at
/// compile time instead of at runtime.
class UserProfile {
  final String id;
  final String fullName;
  final String email;
  final String role;
  final int strikeCount;
  final String accountStatus;
  final DateTime? lastStrikeAt;
  final DateTime? lastPardonAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserProfile({
    this.id = '',
    required this.fullName,
    required this.email,
    this.role = 'student',
    this.strikeCount = 0,
    this.accountStatus = 'ACTIVE',
    this.lastStrikeAt,
    this.lastPardonAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Build a [UserProfile] from a Firestore document snapshot.
  factory UserProfile.fromFirestore(String docId, Object? data) {
    if (data is! Map<String, dynamic>) {
      return UserProfile(id: docId, fullName: '', email: '');
    }
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      try {
        return (value as dynamic).toDate() as DateTime;
      } catch (_) {}
      return null;
    }

    return UserProfile(
      id: docId,
      fullName: data['fullName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: data['role'] as String? ?? 'student',
      strikeCount: (data['strikeCount'] as num?)?.toInt() ?? 0,
      accountStatus:
          data['accountStatus'] as String? ?? 'ACTIVE',
      lastStrikeAt: parseTimestamp(data['lastStrikeAt']),
      lastPardonAt: parseTimestamp(data['lastPardonAt']),
      createdAt: parseTimestamp(data['createdAt']),
      updatedAt: parseTimestamp(data['updatedAt']),
    );
  }

  /// Serialize this profile for Firestore creation.
  ///
  /// Creation-only: writes the default lastStrikeAt/lastPardonAt nulls and a
  /// server timestamp for updatedAt/createdAt. Never reuse for updates.
  Map<String, dynamic> toFirestoreCreate() {
    return {
      'fullName': fullName,
      'email': email,
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
      'strikePercentage': 0,
      'strikeCount': strikeCount,
      'accountStatus': accountStatus,
      'lastStrikeAt': null,
      'lastPardonAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
