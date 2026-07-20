//
//  SupabaseService.swift
//  SchrammScape Calendar
//
//  The app's connection to the shared Supabase backend: authentication,
//  the signed-in user's profile/role, and the client used by SyncEngine.
//

import Foundation
import Supabase

@MainActor
@Observable
final class SupabaseService {
    static let shared = SupabaseService()

    /// Publishable key — safe to embed; row-level security guards the data.
    private static let projectURL = URL(string: "https://ntgalcphmkbdifevyyfd.supabase.co")!
    private static let publishableKey = "sb_publishable_JKWQURcC49qOUEgfegAYEA_zFI3F3xT"

    let client: SupabaseClient

    var isSignedIn = false
    var displayName = ""
    var role = ""
    var authError: String?

    private init() {
        client = SupabaseClient(supabaseURL: Self.projectURL, supabaseKey: Self.publishableKey)
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    /// Restores a persisted session at launch (works offline once signed in).
    func restoreSession() async {
        if client.auth.currentSession != nil {
            isSignedIn = true
            await loadProfile()
        }
    }

    func signIn(email: String, password: String) async {
        authError = nil
        do {
            try await client.auth.signIn(email: email, password: password)
            isSignedIn = true
            await loadProfile()
        } catch {
            authError = error.localizedDescription
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
        isSignedIn = false
        displayName = ""
        role = ""
    }

    private struct Profile: Decodable {
        let displayName: String
        let role: String

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case role
        }
    }

    private func loadProfile() async {
        guard let userID = currentUserID else { return }
        do {
            let profile: Profile = try await client
                .from("profiles")
                .select("display_name, role")
                .eq("user_id", value: userID)
                .single()
                .execute()
                .value
            displayName = profile.displayName
            role = profile.role
        } catch {
            // No profile row yet — the admin creates them in the dashboard.
            role = ""
        }
    }
}
