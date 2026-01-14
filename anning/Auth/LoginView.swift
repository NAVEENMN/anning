import SwiftUI

struct LoginView: View {
    @ObservedObject var vm: AuthViewModel
    @State private var isSignUp = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Welcome to Anning")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Sign up or log in with your .edu email")
                .foregroundStyle(.secondary)

            Picker("", selection: $isSignUp) {
                Text("Sign in").tag(false)
                Text("Create account").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 360)

            VStack(alignment: .leading, spacing: 10) {
                if isSignUp {
                    TextField("Name", text: $vm.name)
                        .textFieldStyle(.roundedBorder)
                }
                
                TextField("Email (.edu)", text: $vm.email)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                SecureField("Password", text: $vm.password)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(width: 360)

            if let err = vm.errorMessage {
                Text(err)
                    .foregroundStyle(.red)
                    .frame(width: 360, alignment: .leading)
            }

            Button(isSignUp ? "Create account" : "Sign in") {
                isSignUp ? vm.signUp() : vm.signIn()
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

