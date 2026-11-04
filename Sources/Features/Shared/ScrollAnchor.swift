import SwiftUI

extension View {
    /// Gives the view a `ScrollViewReader` id whose frame reaches past it by the given margins.
    ///
    /// `proxy.scrollTo(id)` without an anchor scrolls just enough to show the identified frame,
    /// which leaves a row flush against the edge (cutting off the selection glow and the list's
    /// padding at the ends). Scrolling to this larger, invisible frame keeps the margin instead,
    /// and SwiftUI still clamps it at the start and end of the content.
    func scrollAnchor<ID: Hashable>(_ id: ID, horizontal: CGFloat = 0, vertical: CGFloat = 0) -> some View {
        background {
            // The id goes on the clear view itself: negative padding hands it the larger size,
            // while the padding view around it keeps the row's own size.
            Color.clear
                .id(id)
                .padding(.horizontal, -horizontal)
                .padding(.vertical, -vertical)
                .allowsHitTesting(false)
        }
    }
}
