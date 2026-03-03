class ClaudeStableUpdater < Formula
  desc "Periodically checks and updates claude-code@stable cask"
  homepage "https://github.com/marco-antognini-sonarsource/homebrew-tap"
  url "file:///dev/null"
  version "1.0.0"
  sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

  depends_on "jq"
  depends_on "terminal-notifier"

  def install
    # Create the script with embedded content
    (bin/"update-claude-stable").write <<~EOS
      #!/bin/bash

      set -euo pipefail

      readonly TAP_DIR="/opt/homebrew/Library/Taps/marco-antognini-sonarsource/homebrew-tap"
      readonly CASK_FILE="${TAP_DIR}/Casks/claude-code@stable.rb"
      readonly GCS_BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"
      readonly LOG_URL="file:///opt/homebrew/var/log/claude-stable-updater.log"

      # Get current version from cask file
      CURRENT_VERSION=$(grep --extended-regexp '^\\s+version' "${CASK_FILE}" | sed 's/.*"\\(.*\\)".*/\\1/')
      readonly CURRENT_VERSION
      echo "Current version in cask: ${CURRENT_VERSION}"

      # Get latest stable version
      STABLE_VERSION=$(curl --fail --silent --show-error --location "${GCS_BUCKET}/stable")
      readonly STABLE_VERSION
      echo "Latest stable version: ${STABLE_VERSION}"

      if [[ "${CURRENT_VERSION}" == "${STABLE_VERSION}" ]]; then
          echo "✅ Already up to date!"
          terminal-notifier -title "Claude Stable Updater" -message "Already at v${CURRENT_VERSION}" -open "${LOG_URL}" >/dev/null 2>&1 || true
          exit 0
      fi

      echo ""
      echo "🔄 New version available: ${STABLE_VERSION}"
      echo "Fetching checksums..."

      # Get checksums from manifest
      MANIFEST=$(curl --fail --silent --show-error --location "${GCS_BUCKET}/${STABLE_VERSION}/manifest.json")
      readonly MANIFEST

      ARM_CHECKSUM=$(echo "${MANIFEST}" | jq --raw-output '.platforms["darwin-arm64"].checksum')
      readonly ARM_CHECKSUM

      X64_CHECKSUM=$(echo "${MANIFEST}" | jq --raw-output '.platforms["darwin-x64"].checksum')
      readonly X64_CHECKSUM

      X64_LINUX_CHECKSUM=$(echo "${MANIFEST}" | jq --raw-output '.platforms["linux-x64"].checksum')
      readonly X64_LINUX_CHECKSUM

      ARM_LINUX_CHECKSUM=$(echo "${MANIFEST}" | jq --raw-output '.platforms["linux-arm64"].checksum')
      readonly ARM_LINUX_CHECKSUM

      echo "darwin-arm64: ${ARM_CHECKSUM}"
      echo "darwin-x64: ${X64_CHECKSUM}"
      echo "linux-x64: ${X64_LINUX_CHECKSUM}"
      echo "linux-arm64: ${ARM_LINUX_CHECKSUM}"

      echo ""
      echo "📝 Updating ${CASK_FILE}"

      # Update version
      sed -i '' "s/version \\".*\\"/version \\"${STABLE_VERSION}\\"/" "${CASK_FILE}"

      # Update checksums
      sed -i '' "s/arm:          \\".*\\"/arm:          \\"${ARM_CHECKSUM}\\"/" "${CASK_FILE}"
      sed -i '' "s/x86_64:       \\".*\\"/x86_64:       \\"${X64_CHECKSUM}\\"/" "${CASK_FILE}"
      sed -i '' "s/x86_64_linux: \\".*\\"/x86_64_linux: \\"${X64_LINUX_CHECKSUM}\\"/" "${CASK_FILE}"
      sed -i '' "s/arm64_linux:  \\".*\\"/arm64_linux:  \\"${ARM_LINUX_CHECKSUM}\\"/" "${CASK_FILE}"

      echo "✅ Cask file updated to version ${STABLE_VERSION}"
      echo ""
      echo "📦 Committing and pushing changes to homebrew tap..."

      cd "${TAP_DIR}"
      git add Casks/claude-code@stable.rb
      git commit -m "Update claude-code@stable to version ${STABLE_VERSION}"
      git push

      echo "✅ Changes committed and pushed"
      terminal-notifier -title "Claude Stable Updater" -message "Updated to v${STABLE_VERSION}" -open "${LOG_URL}" >/dev/null 2>&1 || true
      echo ""
      echo "To install/upgrade, run:"
      echo "  brew update; and brew outdated --greedy-auto-updates"
    EOS
  end

  service do
    run opt_bin/"update-claude-stable"
    run_type :interval
    interval 3600   # 1 hour in seconds
    working_dir HOMEBREW_PREFIX/"Library/Taps/marco-antognini-sonarsource/homebrew-tap"
    environment_variables PATH: std_service_path_env
    log_path var/"log/claude-stable-updater.log"
    error_log_path var/"log/claude-stable-updater.log"
  end

  test do
    assert_match "Current version in cask:", shell_output("#{bin}/update-claude-stable 2>&1", 0)
  end
end
