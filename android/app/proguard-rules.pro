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

# Room generates <package>.Database_Impl classes that are instantiated reflectively
# by androidx.room.RoomDatabase (e.g. WorkManager's WorkDatabase). R8 full mode strips
# their no-arg constructor, crashing the app at startup with
# NoSuchMethodException: <Database>_Impl.<init>. Keep them intact.
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
-keep class **.Database_Impl {
    <init>();
}
