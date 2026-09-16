#!/bin/bash
#
# Takes a simulator from cold to ready. The timings it prints are worth reading
# when a job gets slower: they are where the minutes are.
#
# Only the boot is allowed to fail the job. Everything after it is warm-up — if
# it does not happen, the job pays for that piece of the cold start itself,
# later, which is exactly where it was paying for it before.

set -uo pipefail

UDID="$1"
STUB="$2"
WORK="$3"
DISPLAY_WARMUP="$4"

BUNDLE_ID="com.nycneighborhoodsquiz.simwarmup"
APP="$WORK/SimWarmup.app"
START=$SECONDS

mkdir -p "$WORK"

log() { printf '[%4ds] %s\n' "$((SECONDS - START))" "$*"; }

# simctl occasionally sits on a cold simulator for as long as you will let it.
# Anything here is worth waiting a while for and nothing here is worth waiting
# forever for, so each command gets a leash.
bounded() {
  local limit="$1" waited=0 pid
  shift

  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$limit" ]; then
      log "gave up after ${limit}s: $*"
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
  wait "$pid"
}

# The first app to be installed and launched on a fresh simulator pays for
# installd starting up and for the runtime's shared cache being built, which is
# minutes of the cold start and has nothing to do with which app it is. So a
# stub app pays it, and the real one arrives to a simulator that has done all
# that already. Linking UIKit and SwiftUI without using them is deliberate:
# loading them is the point.
build_stub() {
  [ -d "$STUB" ] || return 1

  local arch sdk
  arch=$(uname -m)
  [ "$arch" = "arm64" ] || arch=x86_64
  sdk=$(xcrun --sdk iphonesimulator --show-sdk-path) || return 1

  mkdir -p "$APP"
  cp "$STUB/Info.plist" "$APP/Info.plist"
  xcrun clang -target "$arch-apple-ios17.0-simulator" -isysroot "$sdk" \
    -framework UIKit -framework SwiftUI \
    -o "$APP/SimWarmup" "$STUB/main.c"
}

# Kicking the boot off first means the stub app is compiled while the device
# comes up rather than after it.
log "booting $UDID"
xcrun simctl boot "$UDID" > /dev/null 2>&1 || true

STUB_BUILT=no
if build_stub; then
  STUB_BUILT=yes
else
  log "could not build the stub app"
fi

# An install spends its time waiting for installd, and installd comes up as part
# of the boot, so asking for the install now rather than after the boot has
# finished folds the two waits into one.
INSTALLED=no
if [ "$STUB_BUILT" = "yes" ] && bounded 240 xcrun simctl install "$UDID" "$APP"; then
  INSTALLED=yes
  log "installd is up and the stub app is installed"
fi

if ! xcrun simctl bootstatus "$UDID" -b; then
  log "boot failed"
  exit 1
fi
log "booted"

if [ "$STUB_BUILT" = "yes" ] && [ "$INSTALLED" = "no" ]; then
  log "installing the stub app, now that the boot has finished"
  bounded 240 xcrun simctl install "$UDID" "$APP" && INSTALLED=yes
fi

if [ "$INSTALLED" = "yes" ]; then
  log "launching the stub app"
  bounded 180 xcrun simctl launch "$UDID" "$BUNDLE_ID"
  log "the shared cache is built"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null
  xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null
fi

# Dressing the simulator and grabbing one frame off it starts the display
# service, which the first screenshot would otherwise wait minutes for.
if [ "$DISPLAY_WARMUP" = "true" ]; then
  log "setting the status bar and exercising the display"
  xcrun simctl status_bar "$UDID" override \
    --time "9:41" \
    --batteryState charged \
    --batteryLevel 100 \
    --wifiBars 3 \
    --cellularBars 4
  xcrun simctl ui "$UDID" appearance dark
  xcrun simctl ui "$UDID" appearance light
  xcrun simctl io "$UDID" screenshot "$WORK/warm-up.png" > /dev/null
fi

log "ready"
