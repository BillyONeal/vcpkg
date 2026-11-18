#!/bin/sh
set -e

hdiutil attach clt.dmg -mountpoint /Volumes/setup-installer
sudo installer -pkg "/Volumes/setup-installer/Command Line Tools.pkg" -target /
hdiutil detach /Volumes/setup-installer
rm clt.dmg
sudo xcode-select -s /Applications/Xcode.app
curl -fsSL -o "$HOME/Downloads/install-homebrew.sh" https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
NONINTERACTIVE=1 /bin/bash "$HOME/Downloads/install-homebrew.sh"
rm "$HOME/Downloads/install-homebrew.sh"
(echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> "$HOME/.zprofile"
eval "$(/opt/homebrew/bin/brew shellenv)"
brew install autoconf-archive autoconf automake azcopy azure-cli bison cmake gettext gfortran gnu-sed gperf libtool meson nasm ninja pkg-config powershell
mkdir "$HOME/Data"
# NOTE: update this URI when publishing a VM update
curl -fsSL -o "$HOME/Downloads/actions-runner.tar.gz" https://github.com/actions/runner/releases/download/v2.338.2/actions-runner-osx-arm64-2.338.2.tar.gz
mkdir "$HOME/actions-runner"
tar xf "$HOME/Downloads/actions-runner.tar.gz" -C "$HOME/actions-runner"
rm "$HOME/Downloads/actions-runner.tar.gz"
rm guest-prepare.sh
