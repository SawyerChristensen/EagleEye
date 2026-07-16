//
//  MemberContactService.swift
//  EagleEye
//
//  Loads the office contact details and social-media links shown on a
//  representative's profile. Office address, phone, and official website come
//  from the Congress.gov member-detail endpoint; social handles come from the
//  open-source unitedstates/congress-legislators dataset, which Congress.gov
//  doesn't provide.
//

import Foundation

/// Fetches contact information for members of Congress from two sources:
/// Congress.gov (office address, phone, website) and the community-maintained
/// congress-legislators social-media dataset (X, Facebook, YouTube, Instagram).
struct MemberContactService {
    var apiKey: String = CongressService.configuredAPIKey
    var session: URLSession = .shared

    /// The congress-legislators social-media dataset, keyed by Bioguide ID. A
    /// single JSON file covers the whole Congress, so it's fetched once for the
    /// delegation rather than per member.
    static let socialMediaURL = URL(
        string: "https://unitedstates.github.io/congress-legislators/legislators-social-media.json"
    )!

    /// Loads a member's Washington office address, phone, and official website
    /// from Congress.gov. Returns `nil` for sample members (no Bioguide ID) or on
    /// any failure, leaving the profile's contact section to fall back gracefully.
    func officeInfo(forBioguideID bioguideID: String?) async -> OfficeInfo? {
        guard let bioguideID,
              !apiKey.isEmpty, apiKey != CongressService.apiKeyPlaceholder else {
            return nil
        }

        var components = URLComponents(
            string: "https://api.congress.gov/v3/member/\(bioguideID)"
        )!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        guard let url = components.url else { return nil }

        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              let payload = try? JSONDecoder().decode(MemberDetailResponse.self, from: data) else {
            return nil
        }

        let member = payload.member
        return OfficeInfo(
            officeAddress: member.addressInformation?.officeAddress?
                .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            phone: member.addressInformation?.phoneNumber?
                .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            website: member.officialWebsiteUrl
                .flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
    }

    /// Loads the whole social-media dataset once and returns it keyed by Bioguide
    /// ID. Returns an empty map on any failure, so a missing dataset simply hides
    /// the social links rather than failing the profile load.
    func socialLinksByBioguide() async -> [String: [SocialLink]] {
        guard let (data, response) = try? await session.data(from: Self.socialMediaURL),
              let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              let entries = try? JSONDecoder().decode([SocialMediaEntry].self, from: data) else {
            return [:]
        }

        var result: [String: [SocialLink]] = [:]
        for entry in entries {
            guard let bioguide = entry.id.bioguide else { continue }
            let links = entry.social.links
            if !links.isEmpty {
                result[bioguide] = links
            }
        }
        return result
    }

    /// The office fields drawn from Congress.gov's member detail.
    struct OfficeInfo {
        let officeAddress: String?
        let phone: String?
        let website: URL?
    }
}

// MARK: - Wire format

/// Congress.gov member-detail payload — only the contact fields are decoded.
private struct MemberDetailResponse: Decodable {
    let member: Member

    struct Member: Decodable {
        let addressInformation: AddressInformation?
        let officialWebsiteUrl: String?
    }

    struct AddressInformation: Decodable {
        let officeAddress: String?
        let phoneNumber: String?
    }
}

/// One entry from the congress-legislators social-media dataset.
private struct SocialMediaEntry: Decodable {
    let id: ID
    let social: Social

    struct ID: Decodable {
        let bioguide: String?
    }

    struct Social: Decodable {
        let twitter: String?
        let facebook: String?
        let youtube: String?
        let instagram: String?

        /// The present handles as ordered `SocialLink`s (X, Facebook, YouTube,
        /// Instagram), skipping any the member hasn't listed.
        var links: [SocialLink] {
            [
                (SocialLink.Platform.twitter, twitter),
                (.facebook, facebook),
                (.youtube, youtube),
                (.instagram, instagram),
            ].compactMap { platform, handle in
                guard let handle = handle?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !handle.isEmpty else { return nil }
                return SocialLink(platform: platform, handle: handle)
            }
        }
    }
}

private extension String {
    /// `nil` when the string is empty, otherwise itself — for coalescing away
    /// blank API fields.
    var nonEmpty: String? { isEmpty ? nil : self }
}
