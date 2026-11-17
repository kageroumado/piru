// Settings ▸ People on Android. Android keeps one journal, so Settings offers the part of
// Profiles that applies to it: the people paired from other phones, and pairing with someone
// new (ShareSessionView.swift's PeopleSection).

import SwiftUI

struct AndroidPeopleView: View {
    var body: some View {
        List {
            PeopleSection()
        }
        .themedPage()
        .navigationTitle("People")
        .inlineNavigationTitle()
    }
}
