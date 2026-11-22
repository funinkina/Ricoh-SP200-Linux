#!/bin/sh
# Interactive installer for the Ricoh SP 200 driver on macOS.
# Uses the built-in system CUPS; needs only Xcode Command Line Tools.
# Usage: ./install-macos.sh            install (or reinstall)
#        ./install-macos.sh --uninstall
set -eu
cd "$(dirname "$0")"

NAME=Ricoh_SP_200_DDST
FDIR=/Library/Printers/Ricoh/filter
PPD=/Library/Printers/PPDs/Contents/Resources/ricoh-sp200.ppd
JBIG_URL=https://www.cl.cam.ac.uk/~mgk25/jbigkit/download/jbigkit-2.1.tar.gz
JBIG_SHA=de7106b6bfaf495d6865c7dd7ac6ca1381bd12e0d81405ea81e7f2167263d932

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nError: %s\n' "$*" >&2; exit 1; }
ask() { printf '%s ' "$1"; read -r REPLY || { echo; exit 1; }; }

[ "$(uname)" = Darwin ] || die "macOS only. On Linux run: sudo make install"
[ "$(id -u)" -ne 0 ] || die "run without sudo; you'll be asked for your password when needed."

if [ "${1:-}" = --uninstall ]; then
  ask "Remove the Ricoh SP 200 printer and driver? [y/N]"
  case $REPLY in [yY]*) ;; *) exit 0 ;; esac
  sudo lpadmin -x "$NAME" 2>/dev/null || true
  sudo rm -f "$FDIR/rastertoricohjbig" "$PPD"
  sudo rmdir "$FDIR" /Library/Printers/Ricoh 2>/dev/null || true
  say "Uninstalled."
  exit 0
fi

echo "Ricoh SP 200 driver installer for macOS"
echo "This will build the driver, install it into /Library/Printers and add the printer."
ask "Continue? [Y/n]"
case $REPLY in [nN]*) exit 0 ;; esac

say "Checking Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install || true
  die "finish the Command Line Tools install in the popup, then rerun this script."
fi

say "Building the filter"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$JBIG_URL" -o "$TMP/jbigkit.tar.gz" || die "couldn't download jbigkit (check your internet)."
echo "$JBIG_SHA  $TMP/jbigkit.tar.gz" | shasum -a 256 -c - >/dev/null || die "jbigkit checksum mismatch."
tar xzf "$TMP/jbigkit.tar.gz" -C "$TMP"
J=$TMP/jbigkit-2.1/libjbig
cc -O2 -w -I"$J" -o "$TMP/rastertoricohjbig" \
  rastertoricohjbig.c "$J/jbig.c" "$J/jbig_ar.c" -lcups -lcupsimage || die "build failed."

# macOS rasterizes only the imageable area, so make it full-page to match what
# the printer gets from Linux/Windows; point cupsFilter at the absolute path
# (the system filter dir is SIP-protected).
awk -v f="$FDIR/rastertoricohjbig" '
  /^\*cupsFilter:/ { print "*cupsFilter: \"application/vnd.cups-raster 0 " f "\""; next }
  /^\*ImageableArea A4/ { print "*ImageableArea A4/A4: \"0 0 595 842\""; next }
  /^\*ImageableArea Letter/ { print "*ImageableArea Letter/Letter: \"0 0 612 792\""; next }
  { print }
  /^\*ModelName:/ { print "*Product: \"(SP 200 DDST)\""; print "*LanguageEncoding: ISOLatin1" }
' ricoh-sp200.ppd > "$TMP/ricoh-sp200.ppd"

say "Looking for the printer on USB"
while :; do
  URI=$(lpinfo -v 2>/dev/null | awk 'tolower($0) ~ /^direct usb:.*ricoh/ {print $2; exit}')
  [ -n "$URI" ] && break
  ask "Printer not found. Plug it in via USB, switch it on, then press Enter (or q to quit)."
  case $REPLY in [qQ]*) exit 1 ;; esac
done
echo "Found: $URI"

ask "Paper size: [1] A4  [2] Letter  (default 1)"
case $REPLY in 2) SIZE=Letter ;; *) SIZE=A4 ;; esac

say "Installing (you may be asked for your password)"
sudo install -d -o root -g wheel -m 755 "$FDIR" "$(dirname "$PPD")"
sudo install -o root -g wheel -m 755 "$TMP/rastertoricohjbig" "$FDIR/rastertoricohjbig"
sudo install -o root -g wheel -m 644 "$TMP/ricoh-sp200.ppd" "$PPD"
sudo lpadmin -p "$NAME" -D "Ricoh SP 200" -v "$URI" -P "$PPD" -o PageSize="$SIZE" -E
echo "Printer '$NAME' added."

ask "Make it your default printer? [Y/n]"
case $REPLY in [nN]*) ;; *) lpoptions -d "$NAME" >/dev/null ;; esac

ask "Print a test page? [Y/n]"
case $REPLY in
  [nN]*) ;;
  *) printf 'Ricoh SP 200 test page\nPrinted from macOS on %s\n' "$(date)" | lpr -P "$NAME"
     echo "Sent. Check the printer." ;;
esac

say "Done. The printer now appears in every app's Print dialog as \"Ricoh SP 200\"."
echo "To remove later: ./install-macos.sh --uninstall"
