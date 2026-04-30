#!/bin/sh
set -eu

ROOT_DIR="${1:-$(pwd)}"
LOCAL_REPO="${2:-$HOME/.m2/repository}"
BUILD_DIR="$ROOT_DIR/.buildtools-cache"
BUILD_TOOLS_JAR="$BUILD_DIR/BuildTools.jar"
BUILD_TOOLS_URL="https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar"
CRAFTBUKKIT_REPO_URL="https://repo.loohpjames.com/repository"

if ! command -v java >/dev/null 2>&1; then
    echo "[Bookshelf] java is required to bootstrap CraftBukkit dependencies." >&2
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "[Bookshelf] git is required by Spigot BuildTools." >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "[Bookshelf] curl is required to download Spigot BuildTools." >&2
    exit 1
fi

mkdir -p "$BUILD_DIR" "$LOCAL_REPO"

TMP_VERSIONS="$BUILD_DIR/craftbukkit-versions.txt"
find "$ROOT_DIR" -name pom.xml -not -path "$ROOT_DIR/common/pom.xml" -print0 \
    | xargs -0 awk '
        /<artifactId>craftbukkit<\/artifactId>/ { found = 1; next }
        found && /<version>/ {
            gsub(/.*<version>|<\/version>.*/, "", $0);
            print $0;
            found = 0;
        }
    ' \
    | sort -u > "$TMP_VERSIONS"

while IFS= read -r version; do
    [ -n "$version" ] || continue

    artifact="$LOCAL_REPO/org/bukkit/craftbukkit/$version/craftbukkit-$version.jar"
    pom="$LOCAL_REPO/org/bukkit/craftbukkit/$version/craftbukkit-$version.pom"
    pom_url="$CRAFTBUKKIT_REPO_URL/org/bukkit/craftbukkit/$version/craftbukkit-$version.pom"
    if [ -f "$artifact" ]; then
        if curl -fsL "$pom_url" -o "$pom"; then
            rm -f "$LOCAL_REPO/org/bukkit/craftbukkit/$version"/*.lastUpdated
        fi
        echo "[Bookshelf] CraftBukkit $version already exists in local Maven repository."
        continue
    fi

    mkdir -p "$LOCAL_REPO/org/bukkit/craftbukkit/$version"
    artifact_url="$CRAFTBUKKIT_REPO_URL/org/bukkit/craftbukkit/$version/craftbukkit-$version.jar"
    if curl -fL "$artifact_url" -o "$artifact"; then
        if ! curl -fsL "$pom_url" -o "$pom"; then
            cat > "$pom" <<POM
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>org.bukkit</groupId>
    <artifactId>craftbukkit</artifactId>
    <version>$version</version>
    <packaging>jar</packaging>
</project>
POM
        fi
        rm -f "$LOCAL_REPO/org/bukkit/craftbukkit/$version"/*.lastUpdated
        echo "[Bookshelf] Installed CraftBukkit $version from $CRAFTBUKKIT_REPO_URL."
        continue
    fi

    rm -f "$artifact"

    if [ ! -f "$BUILD_TOOLS_JAR" ]; then
        echo "[Bookshelf] Downloading Spigot BuildTools..."
        curl -fL "$BUILD_TOOLS_URL" -o "$BUILD_TOOLS_JAR"
    fi

    rev=$(printf '%s\n' "$version" | sed 's/-R0\.1-SNAPSHOT$//')
    work_dir="$BUILD_DIR/$rev"
    mkdir -p "$work_dir"

    echo "[Bookshelf] Installing CraftBukkit $version with BuildTools --rev $rev..."
    (
        cd "$work_dir"
        java -jar "$BUILD_TOOLS_JAR" --rev "$rev" --compile craftbukkit --disable-java-check
    )

    if [ ! -f "$artifact" ]; then
        echo "[Bookshelf] BuildTools completed but did not install $artifact." >&2
        exit 1
    fi
done < "$TMP_VERSIONS"
