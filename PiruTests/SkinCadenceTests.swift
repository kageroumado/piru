import Foundation
import Testing
@testable import Piru

@Suite("Skin cadence")
struct SkinCadenceTests {
    @Test
    func `Scenes run at 30 fps, stickers at 20, and Low Power Mode halves both`() {
        #expect(SkinBackdrop.frameInterval(stickers: false, lowPower: false) == 1.0 / 30)
        #expect(SkinBackdrop.frameInterval(stickers: true, lowPower: false) == 1.0 / 20)
        #expect(SkinBackdrop.frameInterval(stickers: false, lowPower: true) == 1.0 / 15)
        #expect(SkinBackdrop.frameInterval(stickers: true, lowPower: true) == 1.0 / 10)
    }

    @Test
    func `Only a serious or critical thermal state stops the scene`() {
        #expect(!SkinPower.constrained(.nominal))
        #expect(!SkinPower.constrained(.fair))
        #expect(SkinPower.constrained(.serious))
        #expect(SkinPower.constrained(.critical))
    }

    @Test
    func `The cached snake tape is the game replayed from the start`() {
        let game = SnakeGame(cols: 36, rows: 40, seed: 0x5AAE)
        let tape = game.simulateTape()
        #expect(tape.count == SnakeGame.tapeLength)
        for step in [0, 1, 17, 450, SnakeGame.tapeLength - 1] {
            let cached = game.state(atStep: step)
            #expect(cached.body.map(\.0) == tape[step].body.map(\.0))
            #expect(cached.body.map(\.1) == tape[step].body.map(\.1))
            #expect(cached.food == tape[step].food)
        }
        // Consecutive states differ by one move: the head advances one cell.
        let a = tape[100].body[0], b = tape[101].body[0]
        #expect(abs(a.0 - b.0) + abs(a.1 - b.1) == 1)
    }
}
