import Foundation

/// Top-level namespace for shh's business logic.
///
/// shh is a local API-key vault + proxy + cost tracker for AI-coding tools.
/// `ShhCore` contains the pure Swift business logic used by both the CLI
/// (`shh` binary) and the SwiftUI menubar app. Neither target imports
/// AppKit from ShhCore; both operate on the same underlying state via this
/// module.
public enum Shh {
    public static let version = "0.0.1-dev"
}
