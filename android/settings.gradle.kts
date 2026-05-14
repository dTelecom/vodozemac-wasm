// Top-level Gradle settings for the vodozemac AAR build.
// Single-module project: the AAR module is the root (`rootProject`) rather
// than a sub-project, keeping the directory layout flat.

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "vodozemac"
