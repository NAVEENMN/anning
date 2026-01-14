import SwiftUI

struct AuthGateView: View {
    @StateObject private var vm = AuthViewModel()

    var body: some View {
        Group {
            switch vm.state {
            case .loggedOut:
                LoginView(vm: vm)

            case .needsVerification(let email):
                VerifyEmailView(vm: vm, email: email)

            case .loggedIn:
                ContentView()
            }
        }
        .environmentObject(vm)
    }
}

