import PhotosUI
import SwiftUI
import UIKit

/// Photo grid with Take photo / Library buttons, used after Stop and when editing an entry.
struct PhotoEditor: View {
    @ObservedObject private var store = Store.shared
    @Binding var ids: [String]
    var onAdd: (String) -> Void = { _ in }
    var onRemove: (String) -> Void

    @State private var showCamera = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var viewer: ViewerItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 10) {
            if !ids.isEmpty {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                        Theme.track
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                if let img = store.thumbnail(id) {
                                    Image(uiImage: img).resizable().scaledToFill()
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .contentShape(Rectangle())
                            .onTapGesture { viewer = ViewerItem(ids: ids, index: index) }
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    ids.removeAll { $0 == id }
                                    onRemove(id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 26, height: 26)
                                        .background(Color.black.opacity(0.55), in: Circle())
                                }
                                .buttonStyle(.borderless)
                                .padding(6)
                                .accessibilityLabel("Remove photo")
                            }
                    }
                }
            }
            HStack(spacing: 10) {
                Button {
                    showCamera = true
                } label: {
                    addLabel("Take photo", icon: "camera")
                }
                .buttonStyle(.borderless)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                PhotosPicker(selection: $picked, maxSelectionCount: 10, matching: .images) {
                    addLabel("Library", icon: "photo")
                }
                .buttonStyle(.borderless)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(onImage: { image in add(image) }, onClose: { showCamera = false })
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $viewer) { item in
            PhotoViewer(ids: item.ids, start: item.index)
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        add(image)
                    }
                }
                picked = []
            }
        }
    }

    private func add(_ image: UIImage) {
        guard let id = store.addPhoto(image) else { return }
        ids.append(id)
        onAdd(id)
    }

    private func addLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(Theme.muted)
            Text(title).foregroundStyle(Theme.ink)
        }
        .font(.system(size: 15, weight: .medium))
        .frame(maxWidth: .infinity, minHeight: 52)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: "#B9BBC2"), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .contentShape(Rectangle())
    }
}

/// The iPhone camera.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onClose: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.onClose()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onClose()
        }
    }
}

/// Full-screen photos, swipe between them.
struct PhotoViewer: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    let ids: [String]
    @State private var index: Int

    init(ids: [String], start: Int) {
        self.ids = ids
        _index = State(initialValue: start)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(ids.enumerated()), id: \.offset) { i, id in
                    Group {
                        if let image = store.image(id) {
                            Image(uiImage: image).resizable().scaledToFit()
                        } else {
                            Image(systemName: "photo").foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: ids.count > 1 ? .always : .never))
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.16), in: Circle())
            }
            .padding(.trailing, 16)
            .padding(.top, 8)
            .accessibilityLabel("Close photo")
        }
    }
}
