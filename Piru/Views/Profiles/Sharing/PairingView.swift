import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Your pairing code, and on iPhone the scanner for the other person's. Two
/// people scan each other's codes once, in person; after that each can send
/// the other a session.
struct PairingView: View {
    @Environment(\.profileDirectory) private var directory
    @State private var code: PairingCode?
    @State private var error: String?
    #if os(iOS)
        @State private var scanning = false
        @State private var scanned: URL?
    #endif

    var body: some View {
        List {
            if ShareNameSection.isNeeded(directory.activeProfile) {
                ShareNameSection()
            } else {
                codeSection
            }

            #if os(iOS)
                Section {
                    Button {
                        scanning = true
                    } label: {
                        Label("Scan Their Code", systemImage: "qrcode.viewfinder")
                    }
                }
                .listRowBackground(CardBackground())
            #endif
        }
        .themedPage()
        .navigationTitle("Pair")
        .inlineNavigationTitle()
        .task(id: directory.activeProfile) { makeCode() }
        #if os(iOS)
            // The inbox presents once the scanner is gone, not over its exit.
            .sheet(isPresented: $scanning, onDismiss: {
                if let url = scanned {
                    scanned = nil
                    _ = ShareInbox.shared.handle(url)
                }
            }) {
                PairingScannerSheet { url in
                    scanned = url
                    scanning = false
                }
            }
        #endif
    }

    private var codeSection: some View {
        Section {
            VStack(spacing: Spacing.lg) {
                if let code {
                    PairingQRCode(text: code.url.absoluteString)
                        .frame(maxWidth: 240)
                        .accessibilityLabel(Text("Your pairing code"))
                } else if let error {
                    Text(verbatim: error)
                        .captionSecondary()
                } else {
                    ProgressView()
                }
                HStack(spacing: Spacing.md) {
                    ProfileAvatarView(directory.activeProfile, diameter: 28)
                    Text(verbatim: directory.activeProfile.name)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
        } footer: {
            Text("They scan this code, and you scan theirs. After that you can send each other sessions. Nothing is sent until you choose to.")
        }
        .listRowBackground(CardBackground())
    }

    private func makeCode() {
        do {
            let identity = try ShareIdentityStore.shared.identity(for: directory.activeProfileID)
            code = PairingCode(identity: identity, profile: directory.activeProfile)
        } catch {
            self.error = String(localized: "Piru couldn't make a pairing code: the Keychain is locked or unavailable.")
        }
    }
}

/// A QR code for `text`, black on white with a quiet zone, so it scans in dark
/// mode too.
struct PairingQRCode: View {
    let text: String

    var body: some View {
        if let image = Self.image(for: text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(Spacing.lg)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private static func image(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

/// Asks an owner still called by the default name for a real one before a
/// code or a share carries it to someone else's phone.
struct ShareNameSection: View {
    @Environment(\.profileDirectory) private var directory
    @State private var name = ""

    /// Whether the active profile still has the name Piru gave it.
    static func isNeeded(_ profile: PiruProfile) -> Bool {
        profile.isOwner && profile.name == ProfileRegistry.defaultOwnerName
    }

    var body: some View {
        Section {
            TextField("Your name", text: $name)
                .wordsAutocapitalize()
                .submitLabel(.done)
                .onSubmit(save)
            Button("Save Name", action: save)
                .disabled(trimmed.isEmpty)
        } header: {
            Text("Your Name")
        } footer: {
            Text("The other person sees this name beside your sessions.")
        }
        .listRowBackground(CardBackground())
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        var profile = directory.activeProfile
        if profile.avatar.withPhoto(nil) == .monogram(for: profile.name) {
            profile.avatar = ProfileAvatar.monogram(for: trimmed).withPhoto(profile.avatar.photo)
        }
        profile.name = trimmed
        try? directory.update(profile)
    }
}
