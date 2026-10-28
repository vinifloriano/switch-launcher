import DesignSystem
import InputKit
import Observation
import SwiftUI

/// Sleep Mode: the screen goes dark until any button is pressed.
@MainActor @Observable
public final class SleepModel: InputResponder {
    @ObservationIgnored unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    public func handle(_ button: NintendoButton) {
        app.sound.play(.wake)
        app.popSilently()
    }
}

struct SleepView: View {
    let model: SleepModel

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .onTapGesture { model.handle(.a) }
            .onAppear { NSCursor.setHiddenUntilMouseMoves(true) }
    }
}

extension AppModel {
    func popSilently() {
        guard !stack.isEmpty else { return }
        var copy = stack
        copy.removeLast()
        replaceStack(copy)
    }
}

/// Startup: two Joy-Con–coloured halves snap together with a click, then the HOME Menu fades in.
struct BootView: View {
    let app: AppModel

    @State private var joined = false
    @State private var glow = false
    @Environment(\.ui) private var ui

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            HStack(spacing: ui(joined ? 8 : 60)) {
                RoundedRectangle(cornerRadius: ui(22), style: .continuous)
                    .fill(Color(hex: 0x00C3E3))
                    .frame(width: ui(58), height: ui(160))
                    .offset(x: joined ? 0 : -ui(200))
                RoundedRectangle(cornerRadius: ui(22), style: .continuous)
                    .fill(Color(hex: 0xFF4554))
                    .frame(width: ui(58), height: ui(160))
                    .offset(x: joined ? 0 : ui(200))
            }
            .opacity(joined ? 1 : 0)
            .shadow(color: .white.opacity(glow ? 0.35 : 0), radius: ui(30))
        }
        .contentShape(Rectangle())
        .onTapGesture { app.isBooting = false }
        .task {
            withAnimation(.spring(duration: 0.42, bounce: 0.3)) { joined = true }
            try? await Task.sleep(for: .milliseconds(380))
            app.sound.play(.home)
            withAnimation(.easeOut(duration: 0.4)) { glow = true }
            try? await Task.sleep(for: .milliseconds(250))
            app.sound.play(.boot)
            try? await Task.sleep(for: .milliseconds(1100))
            app.isBooting = false
        }
    }
}
