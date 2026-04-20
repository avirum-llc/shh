import SwiftUI

/// The clickable menubar icon. A lock glyph + the current key count or —
/// eventually — today's spend. See `shh-plan.md` §4 Part 4 for the four
/// states (idle / active / warn / error).
struct MenuBarLabel: View {
    let keyCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
            Text("\(keyCount)")
                .monospacedDigit()
        }
    }
}
