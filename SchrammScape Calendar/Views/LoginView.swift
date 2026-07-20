//
//  LoginView.swift
//  SchrammScape Calendar
//
//  Email + password sign-in to the shared SchrammScape backend.
//  An existing session keeps working offline; only fresh logins need signal.
//

import SwiftUI

struct LoginView: View {
    @State private var supabase = SupabaseService.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
            Text("SchrammScape")
                .font(.largeTitle.bold())
            Text("Sign in to your crew account")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 32)

            if let error = supabase.authError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 32)
            }

            Button {
                isWorking = true
                Task {
                    await supabase.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
                    if supabase.isSignedIn {
                        await SyncEngine.shared.syncNow()
                    }
                    isWorking = false
                }
            } label: {
                HStack {
                    if isWorking { ProgressView().tint(.white) }
                    Text("Sign In")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || password.isEmpty || isWorking)
            .padding(.horizontal, 32)

            Spacer()
            Text("Accounts are created by the administrator.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom)
        }
    }
}
