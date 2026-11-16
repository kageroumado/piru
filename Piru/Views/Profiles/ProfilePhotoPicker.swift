import PhotosUI
import SwiftUI

/// The editor's photo row: the picker opens as soon as Photo is chosen with
/// no photo yet, and a picked photo goes through Move and Scale before it
/// becomes the avatar.
struct ProfilePhotoPickerRow: View {
    @Binding var photo: String?

    @State private var picking = false
    @State private var item: PhotosPickerItem?
    @State private var source: ProfilePhotoSource?
    @State private var working = false
    @State private var failed = false

    var body: some View {
        Button {
            picking = true
        } label: {
            HStack {
                Label(
                    photo == nil ? String(localized: "Choose Photo") : String(localized: "Choose Another Photo"),
                    systemImage: "photo.on.rectangle",
                )
                Spacer()
                if working { ProgressView() }
            }
        }
        .disabled(working)
        .photosPicker(isPresented: $picking, selection: $item, matching: .images, preferredItemEncoding: .compatible)
        .task(id: item) { await load(item) }
        .task { if photo == nil { picking = true } }
        .sheet(item: $source) { source in
            ProfilePhotoCropView(source: source) { crop in
                Task(name: "Save profile photo") { await save(source, crop: crop) }
            }
        }
        .alert("Couldn't Use This Photo", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        working = true
        defer {
            working = false
            self.item = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let prepared = await ProfilePhotoImporter.prepare(data)
        else {
            failed = true
            return
        }
        source = prepared
    }

    /// Writes the file now and hands back its name; the profile takes it on
    /// Save, and a cancelled editor's file goes at the registry's next write.
    private func save(_ source: ProfilePhotoSource, crop: CGRect) async {
        working = true
        defer { working = false }
        guard let encoded = await ProfilePhotoImporter.encode(source, crop: crop),
              let name = try? ProfilePhotoStore.write(encoded.data, fileExtension: encoded.fileExtension)
        else {
            failed = true
            return
        }
        photo = name
    }
}
