import SwiftUI

/// The heart-valve note on a substance page: what activates 5-HT2B (the
/// substance itself, or its class), and where the human cases come from.
///
/// Reference, not advice: it states the mechanism and the exposure the
/// documented cases share, and lets the reader weigh it. A class-declared
/// warning lists the work the class claim rests on.
struct ValvularWarningBanner: View {
    let warning: ValvularWarning
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            InfoBanner(
                icon: "heart.text.square",
                iconTint: .cautionAccent,
                title: "Heart-valve risk with repeated use",
            ) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(mechanismSentence)
                        .captionSecondary()
                        .fixedSize(horizontal: false, vertical: true)
                    Text("The documented cases come from chronic or frequent use: fenfluramine, the ergot drugs pergolide and cabergoline, and heavy MDMA use.")
                        .captionSecondary()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Outside the banner: it combines its children into one VoiceOver
            // element, which would swallow these links.
            if let declaration = warning.declaringClass {
                ForEach(declaration.references) { ref in
                    sourceLine(
                        slug: AppSources.literatureSlug,
                        detail: ref.title,
                        citation: ref.citation,
                        accent: accent,
                    )
                }
            }
        }
    }

    /// The substance's own bindings make the stronger claim, so they speak
    /// whenever they engage; the class speaks for the members never assayed.
    private var mechanismSentence: LocalizedStringResource {
        if !warning.engagedByBindings, let declaration = warning.declaringClass {
            return LocalizedStringResource(
                "\(declaration.classTitle) as a class activate the 5-HT2B receptor, the mechanism behind drug-induced heart-valve damage (valvulopathy).",
                comment: "The argument is a drug class's English name, plural (Phenethylamine psychedelics).",
            )
        }
        return "Activates the 5-HT2B receptor, the mechanism behind drug-induced heart-valve damage (valvulopathy)."
    }
}
