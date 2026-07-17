//
//  StateFlagImage.swift
//  EagleEye
//
//  A state's flag, loaded via `StateFlagDirectory` and cached like a member
//  portrait. Used by the map's state-level view (see TO DO.md) to fill a
//  state's outline instead of a flat party color.
//

import SwiftUI

struct StateFlagImage: View {
    let state: String

    var body: some View {
        CachedAsyncImage(url: StateFlagDirectory.flagURL(forState: state)) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Rectangle().fill(.secondary.opacity(0.15))
        }
    }
}

#Preview {
    StateFlagImage(state: "CA")
        .frame(width: 120, height: 80)
}
