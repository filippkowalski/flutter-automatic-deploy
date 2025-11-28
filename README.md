# Flutter Automatic Deploy

Automate version bumping, changelog generation, and App Store/Play Store releases for Flutter projects.

Disclaimer:
Guys, mind this is a project adjusted specifically to my needs. You should hook up your LLM and ask him to adjust so it works for you. For example, I'm using easy_localization and the pre-check is designed for this package specifically. 

Once you provide it with API Keys from App Store Connect and Google Play, it will automatically build, push, and submit apps for review on both platforms.

PR's or improvement ideas welcome. 

I think you could easily adjust it to any other framework, iOS and Android release are universal so that should be an easy switch.

**Built by Filip Kowalski**
- X: [@filippkowalski](https://x.com/filippkowalski)
- Website: [fkowalski.com](https://fkowalski.com)
- Support: [Buy me a coffee](https://buymeacoffee.com/filipkowalski)

---

<img width="832" height="900" alt="image" src="https://github.com/user-attachments/assets/9e74747b-5fb1-48f9-984b-123b94db2187" />

## Features

- **Universal version bumping** - Works with any Flutter project structure
- **Auto-changelog generation** - Generates changelog from git commits using conventional commits
- **iOS automation** - Build IPA, upload to App Store Connect, and auto-submit for review
- **Android automation** - Build App Bundle, upload to Google Play, and auto-submit for review
- **Pre-release validation** - Validates JSON files, translation coverage, and runs Flutter analyze
- **Git integration** - Auto-commit, create tags, and push to remote

## Quick Start

### 1. Clone or download the scripts

```bash
git clone https://github.com/filippkowalski/flutter-automatic-deploy.git
cd flutter-automatic-deploy
chmod +x bump_version.sh submit_to_app_store.py submit_to_google_play.py
```

### 2. Install globally (optional)

Add an alias to your shell config (`~/.zshrc` or `~/.bashrc`):

```bash
alias bump_version='/path/to/flutter-automatic-deploy/bump_version.sh'
```

Then reload your shell:
```bash
source ~/.zshrc
```

### 3. Set up environment variables (for iOS releases)

```bash
export APP_STORE_API_KEY_ID=your_key_id
export APP_STORE_ISSUER_ID=your_issuer_id
export APP_STORE_P8_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8
```

You can find your API credentials in [App Store Connect > Users and Access > Keys](https://appstoreconnect.apple.com/access/api).

### 4. Install Python dependencies (for App Store submission)

```bash
pip3 install PyJWT requests cryptography
```

## Usage

### Basic Version Bumping

```bash
# Bump patch version (1.0.0 -> 1.0.1)
bump_version patch

# Bump minor version (1.0.0 -> 1.1.0)
bump_version minor

# Bump major version (1.0.0 -> 2.0.0)
bump_version major

# Bump build number only (1.0.0+10 -> 1.0.0+11)
bump_version build

# Set specific version
bump_version 1.14.0+31
```

### Full Release (Build + Upload + Submit)

```bash
# Full release for both platforms
bump_version patch --release

# iOS only
bump_version patch --release --skip-android

# Android only
bump_version patch --release --skip-ios

# Upload without auto-submitting to App Store review
bump_version patch --release --skip-submit
```

### Git Integration

```bash
# Auto-commit version changes
bump_version patch --commit

# Create and push git tag
bump_version patch --push-tag

# Full release with tag push
bump_version patch --release --push-tag
```

### Preview Mode

```bash
# See what would happen without making changes
bump_version patch --dry-run
```

## Options

| Option | Description |
|--------|-------------|
| `major` | Bump major version (1.0.0 -> 2.0.0) |
| `minor` | Bump minor version (1.0.0 -> 1.1.0) |
| `patch` | Bump patch version (1.0.0 -> 1.0.1) |
| `build` | Bump build number only |
| `X.Y.Z+B` | Set specific version |
| `--release` | Build and upload after version bump |
| `--skip-ios` | Skip iOS build |
| `--skip-android` | Skip Android build |
| `--skip-submit` | Upload iOS without auto-submission |
| `--skip-changelog` | Skip changelog generation |
| `--commit` | Auto-commit version changes |
| `--push-tag` | Create and push git tag |
| `--no-tag` | Skip git tag creation |
| `--dry-run` | Preview changes without modifying files |
| `--help` | Show help message |

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `APP_STORE_API_KEY_ID` | For iOS | App Store Connect API Key ID |
| `APP_STORE_ISSUER_ID` | For iOS | App Store Connect Issuer ID |
| `APP_STORE_P8_KEY_PATH` | Optional | Path to .p8 key file (defaults to `~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8`) |
| `GOOGLE_PLAY_SERVICE_ACCOUNT` | Optional | Path to Google Play service account JSON (defaults to `~/.google-play/service-account.json`) |

## Project Structure Support

The script auto-detects Flutter projects in common structures:

```
project/                  # Works from here
project/mobile/           # Works from here (looks for mobile/pubspec.yaml)
project/app/              # Works from here (looks for app/pubspec.yaml)
project/flutter/          # Works from here
```

## Changelog Generation

The script automatically generates changelog entries from git commits using [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` commits go under **Added**
- `fix:` commits go under **Fixed**
- `refactor:`, `perf:`, `style:`, `chore:` go under **Changed**

Example generated changelog:

```markdown
## [1.14.0+32] - 2024-01-15

### Added
- New user authentication flow
- Dark mode support

### Fixed
- Login button not responding on iOS
- Memory leak in image cache

### Changed
- Improved performance of list rendering
```

## Pre-Release Validation

Before releasing, the script validates:

1. **JSON translation files** - Syntax validation
2. **Translation coverage** - Checks all languages have the same keys (if `translation_checker.py` is present)
3. **Flutter analyze** - Runs `flutter analyze` and blocks on errors

## App Store Submission Script

The `submit_to_app_store.py` script can also be used standalone:

```bash
# Submit a specific version
./submit_to_app_store.py 1.13.0

# With project path
./submit_to_app_store.py 1.13.0 --project-path /path/to/project

# Preview mode
./submit_to_app_store.py 1.13.0 --dry-run

# Override bundle ID
./submit_to_app_store.py 1.13.0 --bundle-id com.example.app
```

## Setting Up App Store Connect API

1. Go to [App Store Connect > Users and Access > Keys](https://appstoreconnect.apple.com/access/api)
2. Click the **+** button to create a new API key
3. Give it a name and select **Admin** or **App Manager** role
4. Download the .p8 file (you can only download it once!)
5. Note the **Key ID** and **Issuer ID**
6. Place the .p8 file at `~/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8`
7. Set the environment variables:

```bash
# Add to ~/.zshrc or ~/.bashrc
export APP_STORE_API_KEY_ID=YOUR_KEY_ID
export APP_STORE_ISSUER_ID=YOUR_ISSUER_ID
```

## Setting Up Google Play API

**Important:** Google changed this workflow in 2024. You now create the Service Account in Google Cloud first, then invite it as a user to Play Console.

### Step 1: Google Cloud Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project (or select an existing one)
3. Search for **"Google Play Android Developer API"** and enable it
4. Go to **IAM & Admin > Service Accounts**
5. Click **+ Create Service Account**
   - Name: e.g., `play-deploy`
   - Role: Select **Service Accounts > Service Account User**
6. Click on the created service account email
7. Go to **Keys** tab > **Add Key** > **Create new key**
8. Select **JSON** and download the file
9. Save it to `~/.google-play/service-account.json`

### Step 2: Google Play Console Setup

1. Copy the service account email (e.g., `play-deploy@your-project.iam.gserviceaccount.com`)
2. Go to [Google Play Console](https://play.google.com/console)
3. Navigate to **Users and permissions**
4. Click **Invite new users**
5. Paste the service account email
6. Grant permissions:
   - **App permissions**: Select your app (or "All apps")
   - **Account permissions**: Check "Release apps to testing tracks" and "Release apps to production"
7. Click **Invite user**

### Install Python dependencies (for Google Play)

```bash
pip3 install google-api-python-client google-auth
```

## Google Play Submission Script

The `submit_to_google_play.py` script can also be used standalone:

```bash
# Submit to production
./submit_to_google_play.py 1.13.0+32

# Submit to internal testing track
./submit_to_google_play.py 1.13.0+32 --track internal

# Staged rollout (10%)
./submit_to_google_play.py 1.13.0+32 --track production --rollout 10

# Create as draft (no auto-submit)
./submit_to_google_play.py 1.13.0+32 --draft
```

## Community Forks

- [Dart Version](https://github.com/Indy9000/flutter-automatic-deploy) by [@Indy9000](https://github.com/Indy9000) - A pure Dart implementation of this tool

## License

MIT License - feel free to use in your projects!

---

**If this tool saved you time, consider [buying me a coffee](https://buymeacoffee.com/filipkowalski)!**
