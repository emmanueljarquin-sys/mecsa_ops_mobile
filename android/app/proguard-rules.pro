# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Prevent R8 from removing vital classes for Supabase / Postgrest
-keep class com.supabase.** { *; }
-keepnames class com.supabase.** { *; }
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Firebase / GMS
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Google Maps
-keep class com.google.android.libraries.maps.** { *; }
-keep class com.google.android.gms.maps.** { *; }

# For Retrofit/OkHttp (if used indirectly)
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**

# Preserve Line Numbers for Exception tracking (Sentry/Firebase Crashlytics)
-keepattributes SourceFile,LineNumberTable

# Ignorar advertencias de Play Core (usado internamente por Flutter para deferred components)
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.tasks.**

