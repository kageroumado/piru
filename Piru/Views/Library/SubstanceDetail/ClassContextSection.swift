import SwiftUI

/// The pharmacological family this substance belongs to, as **one row** that
/// opens it.
///
/// The write-up itself — four paragraphs of shared mechanism, kinetics, safety
/// and SAR — lives in Tools ▸ Education ▸ Drug Classes. It is a good read and a
/// bad interruption: unfolded between a dose ladder and a safety card it buries
/// both. Here it is a name and a chevron for whoever wants it.
struct ClassContextSection: View {
    let substance: Substance
    let model: SubstanceDetailModel

    var body: some View {
        if let context = model.classContext, context.hasBody {
            Section {
                NavigationLink(value: PushRoute.drugClass(slug: context.slug)) {
                    VStack(alignment: .leading, spacing: 2) {
                        // `verbatim`: the class name is data, read from the
                        // research write-up, not a catalog key.
                        Text(verbatim: context.title)
                            .font(.body)
                        if context.siblings.count > 1 {
                            Text("^[\(context.siblings.count) other substance](inflect: true)")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Class")
            }
        }
    }
}

extension SubstanceStore.ClassContext {
    /// Whether there is anything to open. A membership row with no research
    /// bodies behind it is a label, not a destination.
    var hasBody: Bool {
        [sharedMechanism, sharedPharmacokinetics, sharedSafety, sarSummary]
            .contains { $0?.isEmpty == false }
    }
}
