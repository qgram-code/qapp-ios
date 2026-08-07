import SwiftUI

/// Full-screen gallery with pinch-to-zoom and swipe-to-dismiss.
struct ImageViewer: View {
    let urls: [URL]
    var startIndex: Int = 0

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int = 0
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black
                .opacity(max(0.55, 1.0 - Double(abs(dragOffset)) / 400.0))
                .ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(urls.enumerated()), id: \.offset) { offset, url in
                    ZoomableImage(url: url)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if abs(value.translation.height) > abs(value.translation.width) {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if abs(value.translation.height) > 130 {
                            dismiss()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = 0
                            }
                        }
                    }
            )

            VStack {
                HStack {
                    if urls.count > 1 {
                        Text("\(index + 1) из \(urls.count)")
                            .font(QFont.caption(13))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.black.opacity(0.4)))
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.black.opacity(0.4)))
                    }
                }
                .padding(QSpacing.lg)
                Spacer()
            }
        }
        .statusBarHidden(true)
        .onAppear {
            index = min(max(0, startIndex), max(0, urls.count - 1))
        }
    }
}

private struct ZoomableImage: View {
    let url: URL

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        RemoteImage(url: url, contentMode: .fit) {
            AnyView(
                ProgressView().tint(.white)
            )
        }
        .scaleEffect(scale)
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    scale = min(max(1, lastScale * value), 4)
                }
                .onEnded { _ in
                    lastScale = scale
                    if scale < 1.02 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            scale = 1
                            lastScale = 1
                        }
                    }
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                scale = scale > 1 ? 1 : 2.4
                lastScale = scale
            }
        }
    }
}
