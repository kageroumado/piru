// The licenses the Android build ships under besides the iOS ones, which About lists after
// them (substitutions.txt, the `ForEach(BundledLicense.all)` rule). The texts are staged from
// android/licenses.

import SwiftUI

extension BundledLicense {
    static let android: [BundledLicense] = [
        BundledLicense(
            name: "Apache License 2.0 with Runtime Library Exception",
            covers: "The Swift runtime, Foundation and Dispatch, which run Piru on Android.",
            resource: "License-Apache-2.0-SwiftRuntime",
        ),
        BundledLicense(
            name: "Apache License 2.0 with Runtime Library Exception",
            covers: "SkipUI and SkipFuseUI, the parts of Skip that draw Piru's screens on Android. Piru's changes to them are in android/vendor in its repository.",
            resource: "License-Apache-2.0-Skip",
        ),
        BundledLicense(
            name: "Mozilla Public License 2.0",
            covers: "Skip's other modules, which run Piru's Swift code on Android. Piru's changes to them are in android/vendor in its repository.",
            resource: "License-MPL-2.0-Skip",
        ),
        BundledLicense(
            name: "Apache License 2.0",
            covers: "Kotlin, AndroidX, Jetpack Compose, Coil, ZXing, Material Symbols, swift-crypto, swift-asn1, swift-jni and swift-android-native.",
            resource: "License-Apache-2.0-Android",
        ),
        BundledLicense(
            name: "Unicode License v3",
            covers: "ICU, the Unicode data behind dates, numbers and text on Android.",
            resource: "License-Unicode-ICU",
        ),
        BundledLicense(
            name: "curl License",
            covers: "curl, part of Foundation's networking on Android.",
            resource: "License-curl",
        ),
        BundledLicense(
            name: "BoringSSL License",
            covers: "BoringSSL, part of Foundation's networking on Android.",
            resource: "License-BoringSSL",
        ),
        BundledLicense(
            name: "BSD 2-Clause License",
            covers: "commonmark-java. Copyright © Robin Stocker.",
            resource: "License-BSD-2-commonmark",
        ),
    ]
}
