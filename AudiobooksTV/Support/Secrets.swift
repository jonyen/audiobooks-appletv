import Foundation

/// Get a free ESV API key at https://api.esv.org/ (create an account, then
/// register an application) and paste it below.
///
/// To keep your key out of git after adding it, run:
///   git update-index --skip-worktree BibleTV/Support/Secrets.swift
enum Secrets {
    static let esvAPIKey = ""
}
