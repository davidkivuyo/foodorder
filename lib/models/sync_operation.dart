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

import 'dart:convert';

/// Status of a queued offline sync operation.
enum SyncOperationStatus {
  pending,
  syncing,
  failed,
  conflict,
}

/// Represents a queued write operation to be executed when back online.
///
/// Every operation is owned by the user who enqueued it (via [ownerUserId]).
/// Replay must never mutate another user's data, so [SyncQueueService] skips
/// operations whose owner does not match the currently authenticated user.
class SyncOperation {
  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final int timestamp;

  /// UID of the user who created this operation.
  ///
  /// Null only for operations persisted by an older app version — those are
  /// never replayed because their owner cannot be verified.
  final String? ownerUserId;

  final int retryCount;
  final SyncOperationStatus status;
  final String? lastError;

  SyncOperation({
    required this.id,
    required this.type,
    required this.payload,
    required this.timestamp,
    this.ownerUserId,
    this.retryCount = 0,
    this.status = SyncOperationStatus.pending,
    this.lastError,
  });

  SyncOperation copyWith({
    String? id,
    String? type,
    Map<String, dynamic>? payload,
    int? timestamp,
    String? ownerUserId,
    int? retryCount,
    SyncOperationStatus? status,
    String? lastError,
  }) {
    return SyncOperation(
      id: id ?? this.id,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      timestamp: timestamp ?? this.timestamp,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      retryCount: retryCount ?? this.retryCount,
      status: status ?? this.status,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'payload': payload,
      'timestamp': timestamp,
      'ownerUserId': ownerUserId,
      'retryCount': retryCount,
      'status': status.name,
      'lastError': lastError,
    };
  }

  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    return SyncOperation(
      id: json['id'] as String,
      type: json['type'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      timestamp: json['timestamp'] as int,
      ownerUserId: json['ownerUserId'] as String?,
      retryCount: (json['retryCount'] as int?) ?? 0,
      status: _statusFromString(json['status'] as String?),
      lastError: json['lastError'] as String?,
    );
  }

  static SyncOperationStatus _statusFromString(String? statusStr) {
    switch (statusStr) {
      case 'syncing':
        return SyncOperationStatus.syncing;
      case 'failed':
        return SyncOperationStatus.failed;
      case 'conflict':
        return SyncOperationStatus.conflict;
      case 'pending':
      default:
        return SyncOperationStatus.pending;
    }
  }

  String encode() => jsonEncode(toJson());

  factory SyncOperation.decode(String jsonStr) =>
      SyncOperation.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncOperation &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          timestamp == other.timestamp &&
          ownerUserId == other.ownerUserId &&
          retryCount == other.retryCount &&
          status == other.status;

  @override
  int get hashCode =>
      id.hashCode ^
      type.hashCode ^
      timestamp.hashCode ^
      ownerUserId.hashCode ^
      retryCount.hashCode ^
      status.hashCode;
}
