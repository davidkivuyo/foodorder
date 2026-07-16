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

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';

class FirebaseMsg {
  final FirebaseMessaging msgService = FirebaseMessaging.instance;

  Future<void> initFCM() async {
    await msgService.requestPermission();

    String? token = await msgService.getToken();
    print("FCM Token: $token");

    FirebaseMessaging.onBackgroundMessage(handleNotification);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("Foreground message received");
      handleNotification(message);
    });
  }
}

@pragma('vm:entry-point')
Future<void> handleNotification(RemoteMessage message) async {
  await Firebase.initializeApp();

  print("Title: ${message.notification?.title}");
  print("Body: ${message.notification?.body}");
}
