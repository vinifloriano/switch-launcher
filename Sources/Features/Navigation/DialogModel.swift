import DesignSystem
import InputKit
import Observation
import SwiftUI

@MainActor @Observable
public final class DialogModel: InputResponder {
    let message: String
    let detail: String?
    let buttons: [String]
    let destructiveIndex: Int?
    var focusedIndex: Int
    @ObservationIgnored private unowned let app: AppModel
    @ObservationIgnored private let onSelect: (Int) -> Void

    init(
        app: AppModel,
        message: String,
        detail: String?,
        buttons: [String],
        destructiveIndex: Int?,
        onSelect: @escaping (Int) -> Void
    ) {
        self.app = app
        self.message = message
        self.detail = detail
        self.buttons = buttons
        self.destructiveIndex = destructiveIndex
        self.focusedIndex = 0
        self.onSelect = onSelect
    }

    public func handle(_ button: NintendoButton) {
        switch button {
        case .left where focusedIndex > 0:
            focusedIndex -= 1
            app.sound.play(.move)
        case .right where focusedIndex < buttons.count - 1:
            focusedIndex += 1
            app.sound.play(.move)
        case .a:
            choose(focusedIndex)
        case .b:
            choose(0)
        default:
            break
        }
    }

    func choose(_ index: Int) {
        app.sound.play(index == 0 ? .back : .select)
        app.dismissDialog()
        onSelect(index)
    }
}

struct DialogView: View {
    let model: DialogModel

    var body: some View {
        ConsoleDialog(
            message: model.message,
            detail: model.detail,
            buttons: model.buttons,
            destructiveIndex: model.destructiveIndex,
            focusedIndex: model.focusedIndex,
            onSelect: model.choose
        )
    }
}
