#!/bin/bash

# Function to increment version
increment_version() {
    local version=$1
    local increment_type=$2

    IFS='.' read -ra version_parts <<< "$version"
    major=${version_parts[0]}
    minor=${version_parts[1]}
    patch=${version_parts[2]}

    case $increment_type in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        *)
            patch=$((patch + 1))
            ;;
    esac

    echo "${major}.${minor}.${patch}"
}

# Get the increment type (default to patch)
increment_type=${1:-patch}

# Get the last tag
last_tag=$(git describe --tags --abbrev=0)

# Remove 'v' prefix if present
last_version=${last_tag#v}

# Increment the version
new_version=$(increment_version "$last_version" "$increment_type")

# Get commits since last tag
commits=$(git log ${last_tag}..HEAD --oneline)

# Create new annotated tag with commits in the message
git tag -a v${new_version} -m "Release v${new_version}

Commits since ${last_tag}:

${commits}"

echo "Created new tag: v${new_version}"
