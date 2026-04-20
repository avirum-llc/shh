import SwiftUI

/// The clickable menubar icon — a key glyph, nothing else. No count, no
/// spend, no text. The menubar dropdown is where state lives. See
/// `shh-plan.md` §4 Part 4 for the four colour states (idle / active /
/// warn / error) that will eventually tint this glyph.
struct MenuBarLabel: View {
    var body: some View {
        Image(systemName: "key.fill")
    }
}
