import Foundation
import Combine
import FirebaseAuth

@MainActor
final class AuthViewModel: ObservableObject {
    enum State: Equatable {
        case loggedOut
        case needsVerification(email: String)
        case loggedIn(uid: String, email: String)
    }

    @Published var state: State = .loggedOut
    @Published var name: String = ""
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        attachListener()
        refreshState()
    }

    deinit {
        if let h = handle { Auth.auth().removeStateDidChangeListener(h) }
    }

    func attachListener() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
            Task { @MainActor in self?.refreshState() }
        }
    }

    func refreshState() {
        guard let user = Auth.auth().currentUser else {
            state = .loggedOut
            return
        }

        let email = user.email ?? ""
        if user.isEmailVerified {
            let uid = user.uid
            persistLocalUser(uid: uid, email: email)
            state = .loggedIn(uid: uid, email: email)
        } else {
            state = .needsVerification(email: email)
        }
    }

    // MARK: - Actions

    func signUp() {
        errorMessage = nil
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !cleanedName.isEmpty else {
            errorMessage = "Name is required."
            return
        }
        guard isAllowedEmail(e) else {
            errorMessage = "Please use a .edu email."
            return
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }

        isBusy = true
        Auth.auth().createUser(withEmail: e, password: password) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.isBusy = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let user = result?.user else {
                    self.errorMessage = "Sign up failed."
                    return
                }
                
                // Set display name before sending verification
                let change = user.createProfileChangeRequest()
                change.displayName = cleanedName
                change.commitChanges { err in
                    Task { @MainActor in
                        if let err { self.errorMessage = err.localizedDescription }
                        user.sendEmailVerification { err in
                            Task { @MainActor in
                                if let err { self.errorMessage = err.localizedDescription }
                                self.state = .needsVerification(email: user.email ?? e)
                            }
                        }
                    }
                }
            }
        }
    }

    func signIn() {
        errorMessage = nil
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard isAllowedEmail(e) else {
            errorMessage = "Please use a .edu email."
            return
        }

        isBusy = true
        Auth.auth().signIn(withEmail: e, password: password) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.isBusy = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let user = result?.user else {
                    self.errorMessage = "Sign in failed."
                    return
                }

                if user.isEmailVerified {
                    let uid = user.uid
                    self.persistLocalUser(uid: uid, email: user.email ?? e)
                    self.state = .loggedIn(uid: uid, email: user.email ?? e)
                    NotificationCenter.default.post(name: .anningAuthDidLogin, object: nil)
                } else {
                    self.state = .needsVerification(email: user.email ?? e)
                }
            }
        }
    }

    func resendVerification() {
        errorMessage = nil
        guard let user = Auth.auth().currentUser else { return }

        isBusy = true
        user.sendEmailVerification { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                self.isBusy = false
                if let error { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func refreshVerificationStatus() {
        errorMessage = nil
        guard let user = Auth.auth().currentUser else { return }

        isBusy = true
        user.reload { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                self.isBusy = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.refreshState()
                // if verified now, trigger project bootstrap
                if case .loggedIn = self.state {
                    NotificationCenter.default.post(name: .anningAuthDidLogin, object: nil)
                }
            }
        }
    }

    func signOut() {
        errorMessage = nil
        try? Auth.auth().signOut()
        name = ""
        email = ""
        password = ""
        state = .loggedOut
        clearLocalUser()
        NotificationCenter.default.post(name: .anningAuthDidLogout, object: nil)
    }

    // MARK: - Policy + local storage

    private func isAllowedEmail(_ email: String) -> Bool {
        // Later you can add a backdoor toggle/allowlist here.
        email.hasSuffix(".edu")
    }

    private func persistLocalUser(uid: String, email: String) {
        UserDefaults.standard.set(uid, forKey: "anning.auth.uid")
        UserDefaults.standard.set(email, forKey: "anning.auth.email")
    }

    private func clearLocalUser() {
        UserDefaults.standard.removeObject(forKey: "anning.auth.uid")
        UserDefaults.standard.removeObject(forKey: "anning.auth.email")
    }
}

extension Notification.Name {
    static let anningAuthDidLogin = Notification.Name("anningAuthDidLogin")
    static let anningAuthDidLogout = Notification.Name("anningAuthDidLogout")
}

