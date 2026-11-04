import Foundation
import SwiftUI

/// Moves a `ScrollViewReader` along with a controller selection.
///
/// A held stick or d-pad repeats every 85 ms, faster than a scroll animation finishes. Starting a
/// new animated `scrollTo` while one is still running can leave the scroll view short of where it
/// was sent (a row or tile half off screen). So quick repeats scroll without animation, and once
/// the presses stop the last scroll is repeated without animation to settle exactly in place.
@MainActor
final class ScrollFollower {
    private var lastMove = Date.distantPast
    private var settle: DispatchWorkItem?

    func scroll<ID: Hashable>(
        _ proxy: ScrollViewProxy,
        to id: ID,
        anchor: UnitPoint? = nil,
        duration: Double = 0.18
    ) {
        let now = Date()
        let isRepeat = now.timeIntervalSince(lastMove) < duration + 0.05
        lastMove = now

        if isRepeat {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(id, anchor: anchor) }
        } else {
            withAnimation(.easeOut(duration: duration)) { proxy.scrollTo(id, anchor: anchor) }
        }

        settle?.cancel()
        let work = DispatchWorkItem {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(id, anchor: anchor) }
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.06, execute: work)
    }

    /// Drops a pending settle, e.g. before jumping somewhere else.
    func cancel() {
        settle?.cancel()
        settle = nil
    }
}
