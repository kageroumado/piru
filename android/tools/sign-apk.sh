#!/bin/zsh
# Signs a release APK with Piru's Android release key: sign-apk.sh <unsigned.apk> <signed.apk>.
#
# The key lives only in the login keychain, as two generic-password items: the PKCS12 keystore
# in base64 (service piru-android-release-keystore) and its password (service
# piru-android-release-password). The keystore is written to a private temporary file for the
# length of the signing and trashed after. Without the key this fails: an APK signed with any
# other key could never update an installed copy.
set -e
TOOLS="${0:A:h}"
. "$TOOLS/env.sh"
piru_require_java || exit 1
piru_require_sdk || exit 1
UNSIGNED="$1"
SIGNED="$2"
BUILD_TOOLS=$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)

KEYSTORE_B64=$(security find-generic-password -a piru -s piru-android-release-keystore -w 2> /dev/null) \
    || { echo "sign-apk: no release keystore in the keychain (piru-android-release-keystore)" >&2; exit 1; }
PASSWORD=$(security find-generic-password -a piru -s piru-android-release-password -w 2> /dev/null) \
    || { echo "sign-apk: no keystore password in the keychain (piru-android-release-password)" >&2; exit 1; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/piru-sign.XXXXXX")
chmod 700 "$WORK"
trap 'trash "$WORK"' EXIT
print -r -- "$KEYSTORE_B64" | base64 -d > "$WORK/release.p12"
chmod 600 "$WORK/release.p12"

"$BUILD_TOOLS/zipalign" -P 16 -f 4 "$UNSIGNED" "$WORK/aligned.apk"
PIRU_KEY_PASSWORD="$PASSWORD" "$BUILD_TOOLS/apksigner" sign \
    --ks "$WORK/release.p12" --ks-type PKCS12 --ks-key-alias piru \
    --ks-pass env:PIRU_KEY_PASSWORD --key-pass env:PIRU_KEY_PASSWORD \
    --v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled true \
    --out "$SIGNED" "$WORK/aligned.apk"
"$BUILD_TOOLS/apksigner" verify --verbose --print-certs "$SIGNED" \
    | grep -E "Verified using v[23]|Signer #1 certificate (DN|SHA-256)" >&2
