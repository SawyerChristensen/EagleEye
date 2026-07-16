//
//  GovernorDetailView.swift
//  EagleEye
//
//  Profile screen shown when a governor is tapped in the Representatives
//  list. Governors carry none of `Representative`'s congressional data (no
//  committees, sponsored bills, or funders yet — see `Governor`), so this is
//  a simple header for now rather than the tabbed profile members get.
//

import SwiftUI

struct GovernorDetailView: View {
    let governor: Governor

    private var partyColor: Color {
        switch governor.party {
        case .democrat: .blue
        case .republican: .red
        case .independent: .purple
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                GovernorPortrait(governor: governor, size: 140)

                VStack(spacing: 4) {
                    Text(governor.name)
                        .font(.title2.bold())
                    Text(governor.roleDescription)
                        .font(.headline)
                        .foregroundStyle(partyColor)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .navigationTitle(governor.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        GovernorDetailView(governor: GovernorDirectory.all[0])
    }
}
