import SwiftUI

/// Three-screen threat-model introduction, shown the first time the user
/// opens the menubar dropdown. See `shh-plan.md` §8 for the threat table
/// and §9 for the UX principle "the threat model is the marketing."
struct FirstRunWindow: View {
    @AppStorage("shh.firstRunCompleted") private var firstRunCompleted = false
    @State private var page = 0
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: threatScreen
                case 1: solutionScreen
                default: callToActionScreen
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)
            .padding(.top, 36)

            footer
        }
        .frame(width: 520, height: 440)
        .background(Tokens.surfaceBase)
    }

    // MARK: - Screens

    private var threatScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            label("The problem")
            headline("Your .env files leak.")
            body("""
            Claude Code reads project `.env` files into its context window. \
            That means your API key can appear in a conversation log. A \
            stray `printenv`, a framework cache, a stack trace in your \
            agent's stdout — any of these can ship the key without you \
            noticing.
            """)
        }
    }

    private var solutionScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            label("What shh does")
            headline("The real key stays in Keychain.")
            body("""
            shh stores your API keys in macOS Keychain, gated by Touch ID. \
            Every AI CLI on your machine sees only a dummy token — useless \
            outside the local proxy. If an agent runs `printenv` now, it \
            gets `shh.anthropic.avirumapps.personal`, not `sk-ant-…`.
            """)
        }
    }

    private var callToActionScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            label("What to do next")
            headline("Three clicks.")
            body("""
            1. Add a key from the menubar (⌘N)
            2. Connect a CLI: Claude Code, Codex, Aider, OpenCode, or Gemini
            3. Open the dashboard (⌘D) and watch spend add up — estimated, \
            aggregated across every provider

            shh stays quiet until you want to look.
            """)
        }
    }

    // MARK: - Parts

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium))
            .tracking(0.04 * 10)
            .foregroundStyle(Tokens.inkFaint)
    }

    private func headline(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .ultraLight))
            .foregroundStyle(Tokens.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func body(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Tokens.inkMuted)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack {
            Button("Skip") {
                complete()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Tokens.inkMuted)

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Tokens.accent : Tokens.inkFaint.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            Button(page < 2 ? "Next" : "Get started") {
                if page < 2 {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        page += 1
                    }
                } else {
                    complete()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Tokens.accent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private func complete() {
        firstRunCompleted = true
        dismissWindow(id: WindowID.firstRun)
    }
}
