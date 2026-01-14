import SwiftUI

struct VerifyEmailView: View {
    @ObservedObject var vm: AuthViewModel
    let email: String

    var body: some View {
        VStack(spacing: 14) {
            Text("Verify your email")
                .font(.title2)
                .fontWeight(.semibold)

            Text("We sent a verification email to:")
                .foregroundStyle(.secondary)

            Text(email)
                .font(.headline)

            Text("After you click the link, come back and press Refresh.")
                .foregroundStyle(.secondary)

            if let err = vm.errorMessage {
                Text(err)
                    .foregroundStyle(.red)
                    .frame(width: 420, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button("Resend email") { vm.resendVerification() }
                Button("Refresh") { vm.refreshVerificationStatus() }
                Button("Sign out") { vm.signOut() }
            }
            .disabled(vm.isBusy)

            if vm.isBusy {
                ProgressView()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

