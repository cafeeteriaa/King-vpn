#!/usr/bin/env python3
"""Configure the generated Flutter Android host to sign release APKs.

The keystore and key.properties are created by the release workflow from
GitHub Actions secrets. This script never creates, prints or commits secrets.
"""
from __future__ import annotations

import pathlib
import sys


KTS_IMPORTS = """import java.io.FileInputStream
import java.util.Properties
"""

KTS_TAIL = r'''
// King VPN production signing. key.properties and the keystore are supplied
// only by the protected GitHub release workflow, never committed to source.
val kingReleaseProperties = Properties()
val kingReleasePropertiesFile = rootProject.file("key.properties")
if (!kingReleasePropertiesFile.exists()) {
    throw GradleException("Missing protected Android release signing properties")
}
FileInputStream(kingReleasePropertiesFile).use { kingReleaseProperties.load(it) }

android {
    signingConfigs {
        create("kingRelease") {
            keyAlias = kingReleaseProperties["keyAlias"] as String
            keyPassword = kingReleaseProperties["keyPassword"] as String
            storeFile = file(kingReleaseProperties["storeFile"] as String)
            storePassword = kingReleaseProperties["storePassword"] as String
        }
    }
    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("kingRelease")
        }
    }
}
'''

GROOVY_SNIPPET = r'''
// King VPN production signing. key.properties and the keystore are supplied
// only by the protected GitHub release workflow, never committed to source.
def kingReleaseProperties = new Properties()
def kingReleasePropertiesFile = rootProject.file("key.properties")
if (!kingReleasePropertiesFile.exists()) {
    throw new GradleException("Missing protected Android release signing properties")
}
kingReleasePropertiesFile.withInputStream { kingReleaseProperties.load(it) }

android {
    signingConfigs {
        kingRelease {
            keyAlias kingReleaseProperties['keyAlias']
            keyPassword kingReleaseProperties['keyPassword']
            storeFile file(kingReleaseProperties['storeFile'])
            storePassword kingReleaseProperties['storePassword']
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.kingRelease
        }
    }
}
'''


def configure(path: pathlib.Path) -> None:
    if not path.is_file():
        raise SystemExit(f"Gradle app file not found: {path}")
    source = path.read_text(encoding="utf-8")
    if "kingReleaseProperties" in source or "kingReleasePropertiesFile" in source:
        raise SystemExit("Release signing block already exists; refusing duplicate injection")
    if path.name.endswith(".kts"):
        if not source.lstrip().startswith("plugins {"):
            raise SystemExit("Unexpected Kotlin Gradle template; refusing unsafe signing injection")
        updated = KTS_IMPORTS + source + "
" + KTS_TAIL
    elif path.name == "build.gradle":
        updated = source + "\n" + GROOVY_SNIPPET
    else:
        raise SystemExit("Expected build.gradle or build.gradle.kts")
    path.write_text(updated, encoding="utf-8")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: configure_release_signing.py <android/app/build.gradle[.kts]>")
    configure(pathlib.Path(sys.argv[1]))
