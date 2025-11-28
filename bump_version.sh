#!/bin/bash

# =============================================================================
# Flutter Automatic Deploy - Universal Version Bumper
# =============================================================================
#
# Built by Filip Kowalski
# X: @filippkowalski
# Website: fkowalski.com
# Support: https://buymeacoffee.com/filipkowalski
#
# Automates version bumping, changelog generation, and App Store/Play Store
# releases for Flutter projects.
#
# =============================================================================
#
# Usage:
#   bump_version [major|minor|patch|build] [--release] [--skip-ios] [--skip-android] [--dry-run]
#   bump_version 1.14.0+31 [options]
#
# Examples:
#   bump_version patch                    # Bump patch version
#   bump_version build --release          # Bump build and release both platforms
#   bump_version patch --release --skip-ios    # Release Android only
#   bump_version minor --dry-run          # Preview changes without modifying files
#
# Environment Variables (required for --release with iOS):
#   APP_STORE_API_KEY_ID     - App Store Connect API Key ID
#   APP_STORE_ISSUER_ID      - App Store Connect Issuer ID
#
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse arguments
BUMP_TYPE=""
RUN_RELEASE=false
SKIP_IOS=false
SKIP_ANDROID=false
DRY_RUN=false
CREATE_TAG=true
PUSH_TAG=false
AUTO_COMMIT=false
SKIP_SUBMIT=false

for arg in "$@"; do
  case $arg in
    major|minor|patch|build)
      BUMP_TYPE="$arg"
      ;;
    --release)
      RUN_RELEASE=true
      CREATE_TAG=true
      ;;
    --skip-ios)
      SKIP_IOS=true
      ;;
    --skip-android)
      SKIP_ANDROID=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --no-tag)
      CREATE_TAG=false
      ;;
    --push-tag)
      PUSH_TAG=true
      CREATE_TAG=true
      ;;
    --commit)
      AUTO_COMMIT=true
      ;;
    --skip-submit)
      SKIP_SUBMIT=true
      ;;
    --help|-h)
      echo "Flutter Automatic Deploy - Universal Version Bumper"
      echo "Built by Filip Kowalski | @filippkowalski | fkowalski.com"
      echo ""
      echo "Usage: bump_version [TYPE] [OPTIONS]"
      echo ""
      echo "Types:"
      echo "  major              Bump major version (1.0.0 -> 2.0.0)"
      echo "  minor              Bump minor version (1.0.0 -> 1.1.0)"
      echo "  patch              Bump patch version (1.0.0 -> 1.0.1)"
      echo "  build              Bump build number only (1.0.0+10 -> 1.0.0+11)"
      echo "  X.Y.Z+B            Set specific version"
      echo ""
      echo "Options:"
      echo "  --release          Build and upload after version bump (auto-creates tag)"
      echo "  --skip-ios         Skip iOS build (with --release)"
      echo "  --skip-android     Skip Android build (with --release)"
      echo "  --push-tag         Create and push git tag to remote"
      echo "  --no-tag           Skip git tag creation"
      echo "  --commit           Auto-commit version changes"
      echo "  --skip-submit      Skip automatic App Store submission (iOS only)"
      echo "  --dry-run          Preview changes without modifying files"
      echo "  --help, -h         Show this help message"
      echo ""
      echo "Environment Variables (for iOS release):"
      echo "  APP_STORE_API_KEY_ID     App Store Connect API Key ID"
      echo "  APP_STORE_ISSUER_ID      App Store Connect Issuer ID"
      echo ""
      echo "Examples:"
      echo "  bump_version patch --push-tag          # Bump, tag, and push tag"
      echo "  bump_version build --release           # Bump, tag, build, upload, submit"
      echo "  bump_version minor --commit --push-tag # Bump, commit, tag, push"
      echo "  bump_version patch --release --skip-submit # Upload without auto-submit"
      exit 0
      ;;
    [0-9]*.[0-9]*.[0-9]*+[0-9]*)
      BUMP_TYPE="$arg"
      ;;
    *)
      echo -e "${RED}Unknown option: $arg${NC}"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Validate bump type
if [ -z "$BUMP_TYPE" ]; then
  echo -e "${RED}Error: Version bump type required${NC}"
  echo "Usage: bump_version [major|minor|patch|build|VERSION] [OPTIONS]"
  echo "Use --help for more information"
  exit 1
fi

# Auto-detect Flutter project root
echo -e "${CYAN}Detecting Flutter project...${NC}"

CURRENT_DIR="$PWD"
PROJECT_ROOT=""
PUBSPEC_PATH=""

# Search up the directory tree for pubspec.yaml
while [[ "$CURRENT_DIR" != "/" ]]; do
  if [ -f "$CURRENT_DIR/pubspec.yaml" ]; then
    PROJECT_ROOT="$CURRENT_DIR"
    PUBSPEC_PATH="$CURRENT_DIR/pubspec.yaml"
    break
  fi

  # Check for common Flutter subdirectories
  for subdir in mobile app flutter; do
    if [ -f "$CURRENT_DIR/$subdir/pubspec.yaml" ]; then
      PROJECT_ROOT="$CURRENT_DIR/$subdir"
      PUBSPEC_PATH="$CURRENT_DIR/$subdir/pubspec.yaml"
      break 2
    fi
  done

  CURRENT_DIR="$(dirname "$CURRENT_DIR")"
done

if [ -z "$PUBSPEC_PATH" ]; then
  echo -e "${RED}Error: Could not find pubspec.yaml${NC}"
  echo "Make sure you're inside a Flutter project directory"
  exit 1
fi

# Determine git root (might be parent of Flutter project)
GIT_ROOT="$PROJECT_ROOT"
while [[ "$GIT_ROOT" != "/" ]]; do
  if [ -d "$GIT_ROOT/.git" ]; then
    break
  fi
  GIT_ROOT="$(dirname "$GIT_ROOT")"
done

if [ ! -d "$GIT_ROOT/.git" ]; then
  echo -e "${YELLOW}Warning: Not a git repository, changelog generation disabled${NC}"
  GIT_ROOT=""
fi

# Extract project name
PROJECT_NAME=$(grep "^name: " "$PUBSPEC_PATH" | sed 's/name: //' | xargs)

echo -e "${GREEN}✓ Found project: ${CYAN}$PROJECT_NAME${NC}"
echo -e "${BLUE}  Project root: $PROJECT_ROOT${NC}"
[ -n "$GIT_ROOT" ] && echo -e "${BLUE}  Git root: $GIT_ROOT${NC}"

# Read current version
CURRENT_VERSION=$(grep "^version: " "$PUBSPEC_PATH" | sed 's/version: //' | xargs)

if [ -z "$CURRENT_VERSION" ]; then
  echo -e "${RED}Error: Could not read version from pubspec.yaml${NC}"
  exit 1
fi

echo ""
echo -e "${BLUE}Current version: ${GREEN}$CURRENT_VERSION${NC}"

# Parse version components
VERSION_PART=$(echo "$CURRENT_VERSION" | cut -d'+' -f1)
BUILD_PART=$(echo "$CURRENT_VERSION" | cut -d'+' -f2)

MAJOR=$(echo "$VERSION_PART" | cut -d'.' -f1)
MINOR=$(echo "$VERSION_PART" | cut -d'.' -f2)
PATCH=$(echo "$VERSION_PART" | cut -d'.' -f3)

# Calculate new version
case $BUMP_TYPE in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    BUILD_PART=$((BUILD_PART + 1))
    NEW_VERSION="$MAJOR.$MINOR.$PATCH+$BUILD_PART"
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    BUILD_PART=$((BUILD_PART + 1))
    NEW_VERSION="$MAJOR.$MINOR.$PATCH+$BUILD_PART"
    ;;
  patch)
    PATCH=$((PATCH + 1))
    BUILD_PART=$((BUILD_PART + 1))
    NEW_VERSION="$MAJOR.$MINOR.$PATCH+$BUILD_PART"
    ;;
  build)
    BUILD_PART=$((BUILD_PART + 1))
    NEW_VERSION="$MAJOR.$MINOR.$PATCH+$BUILD_PART"
    ;;
  *)
    if [[ ! $BUMP_TYPE =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
      echo -e "${RED}Error: Invalid version format${NC}"
      echo "Expected: MAJOR.MINOR.PATCH+BUILD (e.g., 1.14.0+31)"
      exit 1
    fi
    NEW_VERSION="$BUMP_TYPE"
    ;;
esac

echo -e "${BLUE}New version:     ${GREEN}$NEW_VERSION${NC}"

# Generate changelog from git commits
CHANGELOG_CONTENT=""
if [ -n "$GIT_ROOT" ]; then
  echo ""
  echo -e "${CYAN}Generating changelog from git commits...${NC}"

  # Find last version tag
  LAST_TAG=$(cd "$GIT_ROOT" && git tag --sort=-v:refname | grep -E "^v?[0-9]+\.[0-9]+\.[0-9]+" | head -1)

  if [ -n "$LAST_TAG" ]; then
    echo -e "${BLUE}  Last release: $LAST_TAG${NC}"

    # Get commits since last tag
    COMMITS=$(cd "$GIT_ROOT" && git log $LAST_TAG..HEAD --pretty=format:"%s" --no-merges)
  else
    echo -e "${YELLOW}  No previous version tag found, using all commits${NC}"
    COMMITS=$(cd "$GIT_ROOT" && git log --pretty=format:"%s" --no-merges | head -20)
  fi

  # Categorize commits using conventional commits format
  ADDED=""
  CHANGED=""
  FIXED=""
  OTHER=""

  while IFS= read -r commit; do
    if [[ $commit =~ ^feat(\(.*\))?:\ (.+)$ ]]; then
      ADDED="${ADDED}- ${BASH_REMATCH[2]}\n"
    elif [[ $commit =~ ^fix(\(.*\))?:\ (.+)$ ]]; then
      FIXED="${FIXED}- ${BASH_REMATCH[2]}\n"
    elif [[ $commit =~ ^(refactor|perf|style|chore)(\(.*\))?:\ (.+)$ ]]; then
      CHANGED="${CHANGED}- ${BASH_REMATCH[3]}\n"
    elif [[ $commit =~ ^[A-Z] ]]; then
      # Capitalize first letter, likely a feature or change
      if [[ $commit =~ ^(Add|Implement|Create|Build) ]]; then
        ADDED="${ADDED}- $commit\n"
      elif [[ $commit =~ ^(Fix|Resolve|Correct) ]]; then
        FIXED="${FIXED}- $commit\n"
      else
        CHANGED="${CHANGED}- $commit\n"
      fi
    fi
  done <<< "$COMMITS"

  # Build changelog content
  CHANGELOG_CONTENT="## [$NEW_VERSION] - $(date +%Y-%m-%d)\n"

  if [ -n "$ADDED" ]; then
    CHANGELOG_CONTENT="${CHANGELOG_CONTENT}\n### Added\n${ADDED}"
  fi

  if [ -n "$CHANGED" ]; then
    CHANGELOG_CONTENT="${CHANGELOG_CONTENT}\n### Changed\n${CHANGED}"
  fi

  if [ -n "$FIXED" ]; then
    CHANGELOG_CONTENT="${CHANGELOG_CONTENT}\n### Fixed\n${FIXED}"
  fi

  # Show preview
  echo ""
  echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${MAGENTA}Changelog Preview:${NC}"
  echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "$CHANGELOG_CONTENT" | head -20
  echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi

# Confirmation
if [ "$DRY_RUN" = false ]; then
  echo ""
  read -p "$(echo -e ${YELLOW}Update version to $NEW_VERSION? \(y/n\) ${NC})" -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Aborted${NC}"
    exit 0
  fi
else
  echo ""
  echo -e "${CYAN}[DRY RUN] Would update version to $NEW_VERSION${NC}"
fi

# Update pubspec.yaml
if [ "$DRY_RUN" = false ]; then
  echo ""
  echo -e "${CYAN}Updating pubspec.yaml...${NC}"
  # Cross-platform sed: macOS requires -i '', Linux/Git Bash uses -i or -i.bak
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC_PATH"
  else
    sed -i.bak "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC_PATH" && rm -f "${PUBSPEC_PATH}.bak"
  fi

  NEW_VERSION_CHECK=$(grep "^version: " "$PUBSPEC_PATH" | sed 's/version: //' | xargs)
  if [ "$NEW_VERSION_CHECK" == "$NEW_VERSION" ]; then
    echo -e "${GREEN}✓ Version updated successfully${NC}"
  else
    echo -e "${RED}✗ Failed to update version${NC}"
    exit 1
  fi
fi

# Update CHANGELOG.md
CHANGELOG_PATH="$GIT_ROOT/CHANGELOG.md"
if [ -n "$CHANGELOG_CONTENT" ] && [ -f "$CHANGELOG_PATH" ]; then
  if [ "$DRY_RUN" = false ]; then
    echo -e "${CYAN}Updating CHANGELOG.md...${NC}"

    # Insert after the main title
    awk -v new="$CHANGELOG_CONTENT" '
      /^# / && !inserted {
        print
        print ""
        printf "%s\n", new
        inserted=1
        next
      }
      {print}
    ' "$CHANGELOG_PATH" > "$CHANGELOG_PATH.tmp"

    mv "$CHANGELOG_PATH.tmp" "$CHANGELOG_PATH"
    echo -e "${GREEN}✓ CHANGELOG.md updated with generated entries${NC}"
  else
    echo -e "${CYAN}[DRY RUN] Would update CHANGELOG.md${NC}"
  fi
fi

# Auto-commit changes if requested OR if releasing (release requires committed changes for proper tagging)
if ( [ "$AUTO_COMMIT" = true ] || [ "$RUN_RELEASE" = true ] ) && [ "$DRY_RUN" = false ] && [ -n "$GIT_ROOT" ]; then
  echo ""
  echo -e "${CYAN}Committing version changes...${NC}"

  cd "$GIT_ROOT"
  git add "$PUBSPEC_PATH"
  [ -f "$CHANGELOG_PATH" ] && git add "$CHANGELOG_PATH"

  git commit -m "chore: bump version to v$NEW_VERSION

- Updated version in pubspec.yaml
- Generated changelog from git commits

Generated with flutter-automatic-deploy"

  echo -e "${GREEN}✓ Changes committed${NC}"
fi

# Create git tag
if [ "$CREATE_TAG" = true ] && [ "$DRY_RUN" = false ] && [ -n "$GIT_ROOT" ]; then
  echo ""
  echo -e "${CYAN}Creating git tag...${NC}"

  cd "$GIT_ROOT"

  # Check if tag already exists
  if git rev-parse "v$NEW_VERSION" >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: Tag v$NEW_VERSION already exists, skipping${NC}"
  else
    # Create annotated tag with changelog
    TAG_MESSAGE="Release v$NEW_VERSION

$(echo -e "$CHANGELOG_CONTENT" | sed 's/^## \[.*\] - .*$//' | sed '/^$/d' | head -20)"

    git tag -a "v$NEW_VERSION" -m "$TAG_MESSAGE"
    echo -e "${GREEN}✓ Created tag: v$NEW_VERSION${NC}"

    # Push tag if requested
    if [ "$PUSH_TAG" = true ]; then
      echo -e "${CYAN}  Pushing tag to remote...${NC}"
      git push origin "v$NEW_VERSION"
      echo -e "${GREEN}✓ Tag pushed to remote${NC}"
    fi
  fi
elif [ "$CREATE_TAG" = true ] && [ "$DRY_RUN" = true ]; then
  echo ""
  echo -e "${CYAN}[DRY RUN] Would create git tag: v$NEW_VERSION${NC}"
  [ "$PUSH_TAG" = true ] && echo -e "${CYAN}[DRY RUN] Would push tag to remote${NC}"
fi

# Release process
if [ "$RUN_RELEASE" = true ]; then
  if [ "$DRY_RUN" = true ]; then
    echo ""
    echo -e "${CYAN}[DRY RUN] Would run release process${NC}"
    exit 0
  fi

  echo ""
  echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${MAGENTA}Pre-Release Validation Suite${NC}"
  echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  VALIDATION_FAILED=false

  # Check 1: Validate JSON translation files
  TRANSLATIONS_DIR="$PROJECT_ROOT/assets/translations"
  if [ -d "$TRANSLATIONS_DIR" ]; then
    echo -e "${CYAN}Validating JSON translation files...${NC}"
    JSON_ERRORS=0

    for json_file in "$TRANSLATIONS_DIR"/*.json; do
      if [ -f "$json_file" ]; then
        filename=$(basename "$json_file")
        if ! python3 -c "import json; json.load(open('$json_file'))" 2>/dev/null; then
          echo -e "${RED}   ✗ Invalid JSON: $filename${NC}"
          # Show the actual error
          python3 -c "import json; json.load(open('$json_file'))" 2>&1 | head -3 | sed 's/^/     /'
          JSON_ERRORS=$((JSON_ERRORS + 1))
        fi
      fi
    done

    if [ $JSON_ERRORS -gt 0 ]; then
      echo -e "${RED}   ✗ $JSON_ERRORS JSON file(s) have syntax errors${NC}"
      VALIDATION_FAILED=true
    else
      echo -e "${GREEN}   ✓ All JSON files valid${NC}"
    fi

    # Check 2: Translation key coverage (compare all languages to en-US)
    echo -e "${CYAN}Checking translation key coverage...${NC}"
    TRANSLATION_CHECKER="$(dirname "$0")/translation_checker.py"

    if [ -f "$TRANSLATION_CHECKER" ]; then
      # Run the checker and capture output
      TRANSLATION_OUTPUT=$(python3 "$TRANSLATION_CHECKER" "$TRANSLATIONS_DIR" 2>&1)
      TRANSLATION_EXIT=$?

      if [ $TRANSLATION_EXIT -ne 0 ]; then
        # Extract total issues count
        TOTAL_ISSUES=$(echo "$TRANSLATION_OUTPUT" | grep -oP "Total Issues: \K\d+" || echo "?")

        echo -e "${YELLOW}   Warning: Translation coverage issues found (${TOTAL_ISSUES} total)${NC}"
        # Show language summary table
        echo "$TRANSLATION_OUTPUT" | grep -E "^[a-z]{2}-[A-Z]{2}|^-{20}" | head -12 | sed 's/^/     /'
        echo ""
        echo -e "${YELLOW}     Run: python3 $TRANSLATION_CHECKER $TRANSLATIONS_DIR${NC}"
        echo -e "${YELLOW}     for full details${NC}"
        echo ""

        # Ask user if they want to proceed despite translation issues
        read -p "$(echo -e ${YELLOW}Proceed with release despite translation issues? \(y/n\) ${NC})" -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
          echo -e "${RED}   ✗ Release blocked due to translation issues${NC}"
          VALIDATION_FAILED=true
        else
          echo -e "${GREEN}   ✓ Proceeding despite translation issues${NC}"
        fi
      else
        echo -e "${GREEN}   ✓ All translations have 100% key coverage${NC}"
      fi
    else
      echo -e "${YELLOW}   Warning: Translation checker not found, skipping coverage check${NC}"
    fi
  fi

  # Check 3: Flutter analyze (errors only, not warnings)
  echo -e "${CYAN}Running Flutter analyze (errors only)...${NC}"
  cd "$PROJECT_ROOT"
  ANALYZE_OUTPUT=$(flutter analyze 2>&1 || true)
  ERROR_COUNT=$(echo "$ANALYZE_OUTPUT" | grep -E "^\s*error •" | wc -l | xargs)

  if [ "$ERROR_COUNT" -gt 0 ]; then
    echo -e "${RED}   ✗ $ERROR_COUNT error(s) found in Flutter analyze${NC}"
    echo "$ANALYZE_OUTPUT" | grep -E "^\s*error •" | head -5 | sed 's/^/     /'
    VALIDATION_FAILED=true
  else
    echo -e "${GREEN}   ✓ No critical errors in Flutter analyze${NC}"
  fi

  echo ""

  if [ "$VALIDATION_FAILED" = true ]; then
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}Pre-release validation FAILED${NC}"
    echo -e "${RED}   Fix the issues above before releasing.${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 1
  fi

  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}✓ All pre-release validations passed${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  echo ""
  echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${MAGENTA}Starting Release Process${NC}"
  echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  cd "$PROJECT_ROOT"

  # iOS Release
  if [ "$SKIP_IOS" = false ]; then
    echo -e "${CYAN}iOS Release${NC}"

    # Check for required environment variables
    if [ -z "$APP_STORE_API_KEY_ID" ] || [ -z "$APP_STORE_ISSUER_ID" ]; then
      echo -e "${RED}Error: Missing required environment variables for iOS release${NC}"
      echo -e "${YELLOW}Please set:${NC}"
      echo -e "${YELLOW}  export APP_STORE_API_KEY_ID=your_key_id${NC}"
      echo -e "${YELLOW}  export APP_STORE_ISSUER_ID=your_issuer_id${NC}"
      echo ""
      echo -e "${YELLOW}You can find these in App Store Connect > Users and Access > Keys${NC}"
      exit 1
    fi

    echo -e "${BLUE}  Building IPA...${NC}"
    flutter build ipa

    echo -e "${BLUE}  Uploading to App Store Connect...${NC}"
    xcrun altool --upload-app --type ios \
      -f build/ios/ipa/*.ipa \
      --apiKey "$APP_STORE_API_KEY_ID" \
      --apiIssuer "$APP_STORE_ISSUER_ID"

    # Automatically submit for review using App Store Connect API
    if [ "$SKIP_SUBMIT" = false ]; then
        echo ""
        echo -e "${CYAN}Automating App Store submission...${NC}"

        # Check if Python script exists
        SUBMIT_SCRIPT="$(dirname "$0")/submit_to_app_store.py"
        if [ ! -f "$SUBMIT_SCRIPT" ]; then
          echo -e "${YELLOW}Warning: Submission script not found: $SUBMIT_SCRIPT${NC}"
          echo -e "${YELLOW}   Skipping automatic submission${NC}"
        else
          # Check if required Python packages are installed
          if ! python3 -c "import jwt, requests" 2>/dev/null; then
            echo -e "${YELLOW}Warning: Missing Python dependencies${NC}"
            echo -e "${YELLOW}   Install with: pip3 install PyJWT requests cryptography${NC}"
            echo -e "${YELLOW}   Skipping automatic submission${NC}"
          else
            # Run the submission script with FULL version including build number
            python3 "$SUBMIT_SCRIPT" "$NEW_VERSION" --project-path "$PROJECT_ROOT"

            if [ $? -eq 0 ]; then
              echo -e "${GREEN}✓ App Store submission complete${NC}"
            else
              echo -e "${YELLOW}Warning: Submission script encountered issues${NC}"
              echo -e "${YELLOW}   Check App Store Connect for status${NC}"
            fi
          fi
        fi
    else
      echo -e "${YELLOW}Skipping automatic submission (--skip-submit flag)${NC}"
    fi

    echo ""
    echo -e "${GREEN}✓ iOS release complete${NC}"
  else
    echo -e "${YELLOW}Skipping iOS${NC}"
  fi

  # Android Release
  GOOGLE_PLAY_SUCCESS=false
  if [ "$SKIP_ANDROID" = false ]; then
    echo ""
    echo -e "${CYAN}Android Release${NC}"
    echo -e "${BLUE}  Building App Bundle...${NC}"
    flutter build appbundle --release

    echo -e "${GREEN}✓ Android build complete${NC}"

    # Automatically upload to Google Play
    GOOGLE_PLAY_SCRIPT="$(dirname "$0")/submit_to_google_play.py"
    if [ -f "$GOOGLE_PLAY_SCRIPT" ]; then
      # Check if service account is configured
      GOOGLE_PLAY_SERVICE_ACCOUNT="${GOOGLE_PLAY_SERVICE_ACCOUNT:-$HOME/.google-play/service-account.json}"
      if [ -f "$GOOGLE_PLAY_SERVICE_ACCOUNT" ]; then
        echo ""
        echo -e "${CYAN}Uploading to Google Play...${NC}"

        # Check if required Python packages are installed
        if ! python3 -c "from google.oauth2 import service_account; from googleapiclient.discovery import build" 2>/dev/null; then
          echo -e "${YELLOW}Warning: Missing Python dependencies${NC}"
          echo -e "${YELLOW}   Install with: pip3 install google-api-python-client google-auth${NC}"
          echo -e "${YELLOW}   Opening folder for manual upload...${NC}"
          open build/app/outputs/bundle/release
        else
          python3 "$GOOGLE_PLAY_SCRIPT" "$NEW_VERSION" --project-path "$PROJECT_ROOT"

          if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Google Play upload complete${NC}"
            GOOGLE_PLAY_SUCCESS=true
          else
            echo -e "${YELLOW}Warning: Google Play upload encountered issues${NC}"
            echo -e "${YELLOW}   Opening folder for manual upload...${NC}"
            open build/app/outputs/bundle/release
          fi
        fi
      else
        echo -e "${YELLOW}Warning: Google Play service account not configured${NC}"
        echo -e "${YELLOW}   To enable auto-upload, save your service account JSON to:${NC}"
        echo -e "${YELLOW}   ~/.google-play/service-account.json${NC}"
        echo ""
        echo -e "${BLUE}  Opening release folder for manual upload...${NC}"
        open build/app/outputs/bundle/release
      fi
    else
      echo -e "${BLUE}  Opening release folder...${NC}"
      open build/app/outputs/bundle/release
      echo -e "${YELLOW}  -> Upload manually to Google Play Console${NC}"
    fi
  else
    echo -e "${YELLOW}Skipping Android${NC}"
  fi

  # Push commits to remote if --push-tag was specified
  if [ "$PUSH_TAG" = true ] && [ -n "$GIT_ROOT" ]; then
    echo ""
    echo -e "${CYAN}Pushing commits to remote...${NC}"
    cd "$GIT_ROOT"
    git push
    echo -e "${GREEN}✓ Commits pushed${NC}"
  fi

  echo ""
  echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}Release Process Complete!${NC}"
  echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  # Build next steps list based on what was NOT automated
  NEXT_STEPS=()

  # Only show Google Play manual upload if it failed
  if [ "$SKIP_ANDROID" = false ] && [ "$GOOGLE_PLAY_SUCCESS" = false ]; then
    NEXT_STEPS+=("Upload Android App Bundle to Google Play Console")
  fi

  # Only show push instructions if --push-tag was not used
  if [ "$PUSH_TAG" = false ]; then
    NEXT_STEPS+=("Push tag: ${YELLOW}git push origin v$NEW_VERSION${NC}")
    NEXT_STEPS+=("Push commits: ${YELLOW}git push${NC}")
  fi

  # Only show next steps if there are any
  if [ ${#NEXT_STEPS[@]} -gt 0 ]; then
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    STEP_NUM=1
    for step in "${NEXT_STEPS[@]}"; do
      echo -e "  ${BLUE}${STEP_NUM}.${NC} $step"
      STEP_NUM=$((STEP_NUM + 1))
    done
  else
    echo ""
    echo -e "${GREEN}All done! Both stores submitted, commits and tags pushed.${NC}"
  fi
else
  echo ""
  echo -e "${GREEN}Version bump complete!${NC}"

  if [ "$DRY_RUN" = false ]; then
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo -e "  ${BLUE}1.${NC} Review changes in pubspec.yaml and CHANGELOG.md"

    if [ "$AUTO_COMMIT" = false ]; then
      echo -e "  ${BLUE}2.${NC} Commit: ${YELLOW}git add . && git commit -m \"chore: bump version to v$NEW_VERSION\"${NC}"
      NEXT_STEP=3
    else
      NEXT_STEP=2
    fi

    if [ "$CREATE_TAG" = false ]; then
      echo -e "  ${BLUE}${NEXT_STEP}.${NC} Tag: ${YELLOW}git tag v$NEW_VERSION${NC}"
      NEXT_STEP=$((NEXT_STEP + 1))
    fi

    if [ "$PUSH_TAG" = false ] && [ -n "$GIT_ROOT" ]; then
      echo -e "  ${BLUE}${NEXT_STEP}.${NC} Push: ${YELLOW}git push && git push origin v$NEW_VERSION${NC}"
    else
      echo -e "  ${BLUE}${NEXT_STEP}.${NC} Push: ${YELLOW}git push${NC}"
    fi

    echo ""
    echo -e "  ${CYAN}Or run full release: ${YELLOW}bump_version $BUMP_TYPE --release${NC}"
  fi
fi
