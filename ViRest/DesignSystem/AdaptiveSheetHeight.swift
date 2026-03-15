import SwiftUI
import UIKit

enum SheetSizing {
    static func fittedHeight(
        from contentHeight: CGFloat,
        minHeight: CGFloat = 260,
        maxFraction: CGFloat = 0.9,
        extra: CGFloat = 20
    ) -> CGFloat {
        let maxHeight = UIScreen.main.bounds.height * maxFraction
        return Swift.min(maxHeight, Swift.max(minHeight, contentHeight + extra))
    }
}

enum AppBottomSheetStyle {
    static let backgroundColor = Color(white: 0.08)
    static let handleColor = Color.white.opacity(0.2)
    static let handleWidth: CGFloat = 40
    static let handleHeight: CGFloat = 4
    static let topHandlePadding: CGFloat = 12
    static let horizontalPadding: CGFloat = 20
    static let bottomPadding: CGFloat = 24
    static let contentSpacing: CGFloat = 20
}

struct AppBottomSheetHandle: View {
    var body: some View {
        Capsule()
            .fill(AppBottomSheetStyle.handleColor)
            .frame(width: AppBottomSheetStyle.handleWidth, height: AppBottomSheetStyle.handleHeight)
            .frame(maxWidth: .infinity)
            .padding(.top, AppBottomSheetStyle.topHandlePadding)
    }
}

private struct IntrinsicHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func onIntrinsicHeightChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: IntrinsicHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(IntrinsicHeightPreferenceKey.self, perform: action)
    }
}
