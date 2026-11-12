import SwiftUI
import WidgetKit

@main
struct PiruLiveActivityBundle: WidgetBundle {
    /// The language picked in the app's Settings, which this extension's own
    /// defaults never see.
    init() {
        AppLanguageRuntime.applyMirroredChoice()
    }

    var body: some Widget {
        PiruLiveActivity()
    }
}
