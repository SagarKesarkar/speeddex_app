# google_mlkit_text_recognition references the Chinese, Devanagari, Japanese
# and Korean recognisers, but they are optional add-ons. SpeedDex ships only
# the Latin one (number plates), so tell R8 the others are meant to be absent.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit finds its detectors by reflection (component registrars created
# through their no-argument constructors). Without these rules R8 strips
# them and face / plate detection fails in release builds.
-keep class com.google.mlkit.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }

# The Mobile Ads SDK runs background work with WorkManager, whose Room
# database class (WorkDatabase_Impl) is generated and created by name.
# Without these rules R8 strips it and release builds crash at startup.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.impl.** { *; }
