//
//  StateLaw.swift
//  EagleEye
//
//  A bill a governor signed into law, shown on their profile in place of the
//  committee/sponsorship sections `Representative` gets — governors don't sit
//  on congressional committees or sponsor bills, but they do sign them.
//

import Foundation

/// A state bill that has been signed into law by a governor.
struct StateLaw: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    /// A one- or two-sentence plain-language description of what the law does.
    let summary: String
    let dateSigned: Date
    /// Two-letter postal code, matching `Governor.state`.
    let state: String
    /// Link to the bill's official state-legislature page or news coverage, when available.
    let sourceURL: URL?

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        dateSigned: Date,
        state: String,
        sourceURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.dateSigned = dateSigned
        self.state = state
        self.sourceURL = sourceURL
    }
}
