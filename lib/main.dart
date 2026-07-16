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

import 'firebase_msg.dart';
import 'package:campusbite/navigation/router.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e, stack) {
    debugPrint('Firebase init error: $e\n$stack');
    // Continue — app degrades gracefully if Firebase is unavailable.
  }

  try {
    await FirebaseMsg().initFCM();
  } catch (e, stack) {
    debugPrint('FCM init error (non-critical on web): $e\n$stack');
    // FCM is non-essential; the app must start regardless.
  }

  usePathUrlStrategy();
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['Campus Bite'],
      '''
The software components of this application incorporate source code include the Apache version 2.0 Open Source License and its following notice.

Copyright 2026 Campus Bite Contributors, Larason

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
  ''',
    );
  });
  runApp(const MyApp());
}

// The main widget
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      title: 'Food order app',
      theme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.dmSansTextTheme(Theme.of(context).textTheme),
      ),
    );
  }
}

