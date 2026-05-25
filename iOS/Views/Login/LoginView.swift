import SwiftUI
import AuthenticationServices
import GoogleSignIn
import GoogleSignInSwift

struct LoginView: View {
    @State private var email = ""
    @State private var errorMessage: String?
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var gs = GlobalSettings.shared
    let onSignedIn: () -> Void

    init(onSignedIn: @escaping () -> Void = {}) {
        self.onSignedIn = onSignedIn
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                        .padding(.top, 20)
                    Text(localized("歡迎回來"))
                        .font(.largeTitle.bold())

                    Text(localized("新用戶註冊將在驗證後自動創建帳號"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 20)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(localized("取消")) {
                            dismiss()
                        }
                    }
                }

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localized("電子郵件或帳號"))
                            .font(.caption.bold())
                            .foregroundColor(.secondary)

                        TextField(localized("請輸入您的 Email"), text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(12)
                    }

                    Button {
                        signInWithEmail()
                    } label: {
                        Text(localized("下一步"))
                            .bold()
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(email.isEmpty ? Color.gray : Color.blue)
                            .cornerRadius(12)
                    }
                    .disabled(email.isEmpty)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                VStack(spacing: 20) {
                    HStack {
                        Rectangle().frame(height: 0.5).foregroundColor(.secondary.opacity(0.5))
                        Text(localized("或使用以下方式")).font(.footnote).foregroundColor(.secondary)
                        Rectangle().frame(height: 0.5).foregroundColor(.secondary.opacity(0.5))
                    }

                    VStack(spacing: 20) {
                        Button {
                            handleGoogleSignIn()
                        } label: {
                            HStack(spacing: 0) {
                                Image("google_logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 45, height: 45)
                                Text(localized("使用 Google 帳號登錄"))
                                    .font(.body.bold())
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        }

                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            handleAppleSignIn(result)
                        }
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                Spacer()

                Button(localized("已有帳號？立即登錄")) {
                    signInWithEmail()
                }
                .font(.footnote)
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 24)
        }
    }

    private func signInWithEmail() {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty else { return }
        guard normalizedEmail.contains("@") else {
            errorMessage = localized("請輸入有效的 Email")
            return
        }

        errorMessage = nil
        gs.signIn(
            displayName: normalizedEmail,
            email: normalizedEmail,
            provider: "Email",
            userIdentifier: normalizedEmail
        )
        completeSignIn()
    }

    private func handleGoogleSignIn() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            errorMessage = localized("無法取得登入視窗")
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { signInResult, error in
            if let error {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                }
                return
            }

            guard let result = signInResult else {
                DispatchQueue.main.async {
                    errorMessage = localized("Google 登入失敗")
                }
                return
            }

            let profile = result.user.profile
            let email = profile?.email ?? result.user.userID ?? ""
            let name = profile?.name ?? email

            DispatchQueue.main.async {
                gs.signIn(
                    displayName: name,
                    email: email,
                    provider: "Google",
                    userIdentifier: result.user.userID ?? email
                )
                completeSignIn()
            }
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = localized("Apple 登入失敗")
                return
            }

            let formatter = PersonNameComponentsFormatter()
            let name = credential.fullName.flatMap { formatter.string(from: $0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            let previousAppleUser = gs.accountProvider == "Apple" && gs.accountUserIdentifier == credential.user
            let persistedName = previousAppleUser ? gs.accountDisplayName : ""
            let persistedEmail = previousAppleUser ? gs.accountEmail : ""
            let displayName = !name.isEmpty ? name : (!persistedName.isEmpty ? persistedName : localized("Apple 使用者"))
            let email = credential.email ?? (!persistedEmail.isEmpty ? persistedEmail : credential.user)
            gs.signIn(
                displayName: displayName,
                email: email,
                provider: "Apple",
                userIdentifier: credential.user
            )
            completeSignIn()
        case .failure(let error):
            errorMessage = appleAuthorizationMessage(for: error)
            return
        }
    }

    private func completeSignIn() {
        onSignedIn()
        ICloudSyncManager.shared.syncAfterSignIn()
        dismiss()
    }

    private func appleAuthorizationMessage(for error: Error) -> String {
        guard let authorizationError = error as? ASAuthorizationError else {
            return error.localizedDescription
        }

        switch authorizationError.code {
        case .canceled:
            return localized("已取消 Apple 登錄")
        case .failed:
            return localized("Apple 登錄失敗，請稍後再試")
        case .invalidResponse:
            return localized("Apple 登錄回應無效")
        case .notHandled:
            return localized("Apple 登錄未完成，請重試")
        case .unknown:
            return localized("無法完成 Apple 登錄，請確認已開啟 Sign in with Apple 並使用支援的 Apple ID")
        default:
            return localized("Apple 登錄失敗")
        }
    }
}


#Preview {
    LoginView()
}
