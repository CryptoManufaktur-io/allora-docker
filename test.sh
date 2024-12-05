#!/usr/bin/env bash
set -euo pipefail

compare_versions() {
    current=$1
    new=$2

    # Extract major, minor, and patch versions
    major_current=$(echo "$current" | cut -d. -f1 | sed 's/v//')
    major_new=$(echo "$new" | cut -d. -f1 | sed 's/v//')

    minor_current=$(echo "$current" | cut -d. -f2)
    minor_new=$(echo "$new" | cut -d. -f2)

    patch_current=$(echo "$current" | cut -d. -f3)
    patch_new=$(echo "$new" | cut -d. -f3)

    # Compare major versions
    if [ "$major_current" -lt "$major_new" ]; then
        __should_update=2
        return
    elif [ "$major_current" -gt "$major_new" ]; then
        __should_update=0
        return
    fi

    # Compare minor versions
    if [ "$minor_current" -lt "$minor_new" ]; then
        __should_update=2
        return
    elif [ "$minor_current" -gt "$minor_new" ]; then
        __should_update=0
        return
    fi

    # Compare patch versions
    if [ "$patch_current" -lt "$patch_new" ]; then
        __should_update=1
        return
    elif [ "$patch_current" -gt "$patch_new" ]; then
        __should_update=0
        return
    fi

    # Versions are the same
    __should_update=0
}


compare_versions v0.6.0 0.7.0
echo $__should_update
