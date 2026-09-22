nonisolated extension SubstanceCategory {
    /// The Oklch seed the category's colorset is derived from.
    var oklchSeed: Oklch {
        switch self {
        case .stimulant: Oklch(l: 0.765, c: 0.175, h: 62.6)
        case .psychedelic: Oklch(l: 0.615, c: 0.213, h: 312.4)
        case .dissociative: Oklch(l: 0.707, c: 0.133, h: 233.9)
        case .dysdelic: Oklch(l: 0.493, c: 0.132, h: 333.7)
        case .deliriant: Oklch(l: 0.579, c: 0.058, h: 94.6)
        case .opioid: Oklch(l: 0.654, c: 0.232, h: 28.7)
        case .benzodiazepine: Oklch(l: 0.603, c: 0.218, h: 257.4)
        case .gabapentinoid: Oklch(l: 0.529, c: 0.191, h: 278.3)
        case .empathogen: Oklch(l: 0.65, c: 0.238, h: 17.9)
        case .cannabinoid: Oklch(l: 0.73, c: 0.194, h: 147.5)
        case .nootropic: Oklch(l: 0.7, c: 0.111, h: 212.8)
        case .ampakine: Oklch(l: 0.812, c: 0.156, h: 138.5)
        case .eugeroic: Oklch(l: 0.807, c: 0.137, h: 76.4)
        case .depressant: Oklch(l: 0.638, c: 0.073, h: 261.5)
        case .orexinAntagonist: Oklch(l: 0.537, c: 0.117, h: 287.8)
        case .antidepressant: Oklch(l: 0.865, c: 0.177, h: 90.4)
        case .antipsychotic: Oklch(l: 0.748, c: 0.13, h: 189.1)
        case .analgesic: Oklch(l: 0.632, c: 0.064, h: 72.8)
        case .antihistamine: Oklch(l: 0.636, c: 0.092, h: 356.7)
        case .cardiovascular: Oklch(l: 0.697, c: 0.193, h: 26.6)
        case .antimicrobial: Oklch(l: 0.766, c: 0.094, h: 207.8)
        case .gastrointestinal: Oklch(l: 0.811, c: 0.152, h: 70.2)
        case .respiratory: Oklch(l: 0.767, c: 0.108, h: 230.4)
        case .endocrine: Oklch(l: 0.701, c: 0.162, h: 313.4)
        case .immunological: Oklch(l: 0.67, c: 0.177, h: 255.7)
        case .supplement: Oklch(l: 0.778, c: 0.161, h: 150.2)
        case .peptide: Oklch(l: 0.702, c: 0.1, h: 244.0)
        case .anticonvulsant: Oklch(l: 0.693, c: 0.114, h: 298.9)
        case .other: Oklch(l: 0.648, c: 0.007, h: 285.9)
        }
    }
}
