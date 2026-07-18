# Proguard rules for CampusBite
# Add project specific Proguard rules here.
# By default, the flags in this file are appended to flags specified
# in /usr/local/google/home/android-sdk/tools/proguard/proguard-android.txt
# You can edit the include paths and targets as needed.

# Flutter Wrapper / Engine rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Don't warn for missing Play Core split install dependencies (used by PlayStoreDeferredComponentManager)
-dontwarn com.google.android.play.core.**
