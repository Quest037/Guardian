import SwiftUI
import AppKit

struct TacticalSplashView: View {
    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.07).ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .stroke(Color.cyan.opacity(0.28), lineWidth: 2)
                        .frame(width: 170, height: 170)
                    Circle()
                        .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
                        .frame(width: 120, height: 120)
                    Circle()
                        .fill(Color.cyan.opacity(pulse ? 0.28 : 0.08))
                        .frame(width: 18, height: 18)

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color.cyan.opacity(0.75), Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 170, height: 2)
                        .rotationEffect(.degrees(spin ? 360 : 0))

                    if let splashLogo = SplashLogoLoader.logoImage {
                        Image(nsImage: splashLogo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 62, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
                }

                Text("GUARDIAN HQ")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("SECURE MISSION OPERATIONS")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(3.0)
                    .foregroundStyle(Color.cyan.opacity(0.9))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                spin = true
            }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private enum SplashLogoLoader {
    static let logoImage: NSImage? = {
        if let bundledIconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let bundledIcon = NSImage(contentsOf: bundledIconURL) {
            return bundledIcon
        }
        return nil
    }()
}
