# Consumer ProGuard / R8 rules. Applied automatically to apps that
# depend on this AAR.
#
# UniFFI Kotlin bindings reach into JNI-loaded code by reflective lookup
# of class names. Keep the public surface so R8/ProGuard doesn't strip or
# rename the types JNA needs to find.
-keep class com.dtelecom.vodozemac.** { *; }
