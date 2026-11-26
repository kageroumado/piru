#if DEBUG
    import Foundation
    import SwiftData

    extension PerfTour {
        /// Every flow, in run order. A flow's name is what `-piruPerfFlows` and
        /// `pipeline/perf/run.py --flows` take; a step's name is stable, because
        /// the report and the baseline key on `<flow>/<step>`.
        static let catalog: [Flow] = [
            Flow(name: "journal-scroll", steps: JournalGrouping.allCases.map { grouping in
                Step("scroll-\(grouping.rawValue.lowercased())") { driver in
                    driver.grouping(grouping)
                    driver.tab(.journal)
                    await driver.wait(1.2)
                    return await driver.scrollEndToEnd()
                }
            }),
            Flow(name: "timeline-scroll", steps: [
                Step("open") { driver in
                    driver.push(.timeline, in: .journal)
                    await driver.wait(1.5)
                    return nil
                },
                Step("scroll") { driver in
                    await driver.scrollEndToEnd(budget: 15)
                },
            ]),
            Flow(name: "open-close", steps: [
                Step("entries-30") { driver in
                    driver.tab(.journal)
                    let entries = driver.newestEntries(30)
                    for entry in entries {
                        driver.present(.entryDetail(timestamp: entry.timestamp, id: entry.id))
                        await driver.wait(0.45)
                        driver.dismiss()
                        await driver.wait(0.35)
                    }
                    return "\(entries.count) entries"
                },
                Step("sessions-30") { driver in
                    let sessions = driver.newestSessions(30)
                    for session in sessions {
                        driver.push(.session(id: session.id), in: .journal)
                        await driver.wait(0.5)
                        driver.navigator.resetAllPaths()
                        await driver.wait(0.35)
                    }
                    return "\(sessions.count) sessions"
                },
            ]),
            Flow(name: "quicklog", steps: (1 ... 4).map { round in
                Step("log-\(round)") { driver in
                    driver.tab(.journal)
                    driver.present(.quickLog(routine: nil))
                    await driver.wait(0.9)
                    let typed = await driver.type(["caf", "ibu", "the", "mag"][round - 1], interval: 0.08)
                    await driver.wait(0.4)
                    driver.endEditing()
                    driver.dismiss()
                    logStagedDoses(round: round, in: driver.activeContext)
                    await driver.wait(1.0)
                    return typed
                }
            }),
            Flow(name: "library-search", steps: [
                Step("type-fast") { driver in
                    driver.tab(.library)
                    await driver.wait(0.6)
                    driver.tab(.search)
                    await driver.wait(0.8)
                    let first = await driver.type("methylphenidate", interval: 0.07)
                    await driver.wait(0.6)
                    let second = await driver.type("ketamine", interval: 0.07)
                    await driver.wait(0.6)
                    let third = await driver.type("alpr", interval: 0.05)
                    await driver.wait(0.8)
                    driver.endEditing()
                    return first ?? second ?? third
                },
                // Names the result titles don't contain — a brand and a localized
                // title — so the overlay's exact-name fallback runs on each one.
                // "ketamina" is no batch key: a miss here is main-actor SQL.
                Step("type-aliases") { driver in
                    driver.tab(.search)
                    await driver.wait(0.8)
                    let first = await driver.type("concerta", interval: 0.07)
                    await driver.wait(0.6)
                    let second = await driver.type("ketamina", interval: 0.07)
                    await driver.wait(0.8)
                    driver.endEditing()
                    return first ?? second
                },
            ]),
            Flow(name: "substance-pages", steps: ["MDMA", "Ketamine", "Methylphenidate", "Caffeine", "Alprazolam"].flatMap { name in
                [
                    Step("page-\(name.lowercased())") { driver in
                        driver.push(.substance(name: name), in: .library)
                        await driver.wait(1.2)
                        return await driver.scrollEndToEnd(budget: 4)
                    },
                    Step("pharmacology-\(name.lowercased())") { driver in
                        driver.push(.substanceData(name: name, section: .pharmacology), in: .library)
                        await driver.wait(1.2)
                        return nil
                    },
                    Step("sources-\(name.lowercased())") { driver in
                        driver.push(.substance(name: name), in: .library)
                        await driver.wait(0.5)
                        driver.present(.doseSources(substance: name, route: .oral))
                        await driver.wait(1.2)
                        driver.dismiss()
                        await driver.wait(0.5)
                        return nil
                    },
                ]
            }),
            Flow(name: "insights", steps: [
                Step("overview") { driver in
                    driver.tab(.insights)
                    await driver.wait(1.5)
                    return await driver.scrollEndToEnd(budget: 4)
                },
            ] + Insight.allCases.map { insight in
                Step("insight-\(insight.rawValue)") { driver in
                    driver.push(.insight(insight), in: .insights)
                    await driver.wait(1.8)
                    return nil
                }
            } + InsightGroup.allCases.map { group in
                Step("group-\(group.rawValue)") { driver in
                    driver.push(.insightGroup(group), in: .insights)
                    await driver.wait(1.8)
                    return nil
                }
            }),
            Flow(name: "stats-ranges", steps: [
                Step("all-ranges") { driver in
                    driver.push(.insight(.usage), in: .insights)
                    await driver.wait(1.5)
                    // The range lives in the screen's private state; the model it
                    // drives is run directly for each range instead.
                    let entries = (try? driver.activeContext.fetch(FetchDescriptor<DoseEntry>())) ?? []
                    let colors = (try? driver.activeContext.fetch(FetchDescriptor<SubstanceColor>())) ?? []
                    let model = UsageAnalyticsModel()
                    for range in UsageTimeRange.allCases {
                        await model.refresh(entries: entries, colors: colors, range: range)
                    }
                    return "\(UsageTimeRange.allCases.count) ranges over \(entries.count) doses"
                },
            ]),
            Flow(name: "tab-storm", steps: [
                Step("switch-60") { driver in
                    let tabs: [TabID] = [.journal, .library, .tools, .insights, .search]
                    for index in 0 ..< 60 {
                        driver.tab(tabs[index % tabs.count])
                        await driver.wait(0.05)
                    }
                    driver.tab(.journal)
                    await driver.wait(0.5)
                    return nil
                },
            ]),
            Flow(name: "skins", steps: [
                Step("try-each") { driver in
                    let store = SkinStore.shared
                    let original = store.chosen
                    driver.tab(.journal)
                    driver.present(.skins)
                    await driver.wait(1.0)
                    var worn = 0
                    for skin in Skin.available {
                        store.setSkin(skin)
                        await driver.wait(0.9)
                        if store.chosen == skin { worn += 1 }
                    }
                    store.setSkin(original)
                    driver.dismiss()
                    await driver.wait(0.6)
                    return "\(worn) of \(Skin.available.count) worn"
                },
            ]),
            Flow(name: "profile-switch", steps: [
                Step("switch-each") { driver in
                    let directory = ProfileDirectory.shared
                    let profiles = directory.profiles
                    guard profiles.count > 1 else { return "one profile" }
                    let home = directory.activeProfileID
                    for profile in profiles + profiles where profile.id != directory.activeProfileID {
                        await ProfileSwitcher.switchTo(profile.id)
                        await driver.wait(1.0)
                    }
                    await ProfileSwitcher.switchTo(home)
                    await driver.wait(1.0)
                    return "\(profiles.count) profiles"
                },
            ]),
            Flow(name: "export-import", steps: [
                Step("export") { driver in
                    do {
                        let data = try await DataExportImport.exportJSONInBackground(format: .piru, context: driver.activeContext)
                        try data.write(to: driver.directory.appending(path: "export.json"), options: .atomic)
                        return "\(data.count / 1024) KB"
                    } catch {
                        return "export failed: \(error.localizedDescription)"
                    }
                },
                Step("wipe-and-import") { driver in
                    do {
                        let data = try Data(contentsOf: driver.directory.appending(path: "export.json"))
                        let context = driver.activeContext
                        try DataExportImport.deleteAll(context: context)
                        try context.save()
                        try DataExportImport.importJSON(data: data, context: context, mode: .replace)
                        DataExportImport.refreshLiveStores(container: ProfileDirectory.shared.activeContainer)
                        let count = (try? context.fetchCount(FetchDescriptor<DoseEntry>())) ?? 0
                        await driver.wait(1.0)
                        return "\(count) doses after import"
                    } catch {
                        return "import failed: \(error.localizedDescription)"
                    }
                },
            ]),
            Flow(name: "backup-restore", steps: [
                Step("seal") { driver in
                    do {
                        let plaintext = try DataExportImport.exportJSON(format: .piru, context: driver.activeContext)
                        let sealed = try await Task.detached { try BackupCrypto.encryptWithPassphrase(plaintext, passphrase: passphrase) }.value
                        try sealed.write(to: driver.directory.appending(path: "backup.piruenc"), options: .atomic)
                        return "\(sealed.count / 1024) KB"
                    } catch {
                        return "seal failed: \(error.localizedDescription)"
                    }
                },
                Step("restore-replace") { driver in
                    do {
                        let sealed = try Data(contentsOf: driver.directory.appending(path: "backup.piruenc"))
                        let plaintext = try await Task.detached { try BackupCrypto.decrypt(sealed, passphrase: passphrase) }.value
                        try BackupManager.shared.apply(journal: plaintext, strategy: .replace, context: driver.activeContext, customStore: .shared)
                        DataExportImport.refreshLiveStores(container: ProfileDirectory.shared.activeContainer)
                        await driver.wait(1.0)
                        return nil
                    } catch {
                        return "restore failed: \(error.localizedDescription)"
                    }
                },
            ]),
            Flow(name: "storms", steps: [
                Step("present-dismiss-20") { driver in
                    driver.tab(.journal)
                    for _ in 0 ..< 20 {
                        driver.present(.settings)
                        await driver.wait(0.08)
                        driver.dismiss()
                        await driver.wait(0.08)
                    }
                    await driver.wait(0.8)
                    return nil
                },
                Step("double-present-10") { driver in
                    let entry = driver.newestEntries(1).first
                    for _ in 0 ..< 10 {
                        if let entry {
                            driver.present(.entryDetail(timestamp: entry.timestamp, id: entry.id))
                            driver.present(.entryDetail(timestamp: entry.timestamp, id: entry.id))
                        }
                        await driver.wait(0.4)
                        driver.navigator.dismissAll()
                        await driver.wait(0.4)
                    }
                    return entry == nil ? "no entries" : nil
                },
                Step("reversed-flings") { driver in
                    driver.grouping(.timeline)
                    driver.tab(.journal)
                    await driver.wait(1.0)
                    return await driver.reversedFlings(12)
                },
            ]),
        ]

        /// The fixture passphrase the backup flow seals with; it protects nothing.
        private nonisolated static let passphrase = "perf-fixture-passphrase"

        /// The doses a quick-log round commits, through the same batch path the
        /// sheet's Save uses, so each round pays the real commit cost.
        private static func logStagedDoses(round: Int, in context: ModelContext) {
            let now = Date.now.addingTimeInterval(Double(round) * 60)
            let staged: [(String, Double, String)] = [("Caffeine", 90, "mg"), ("L-Theanine", 200, "mg"), ("Ibuprofen", 400, "mg")]
            let entries = staged.map { name, amount, unit in
                DoseEntry(substance: name, amount: amount, unit: unit, substanceUID: SubstanceLibrary.substanceUID(for: name), timestamp: now, tags: ["perf"])
            }
            let colors = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
            DoseLogService.shared.logBatch(entries.map { ($0, SubstanceLibrary.lookup($0.substance)) }, colors: colors, in: context)
        }
    }
#endif
