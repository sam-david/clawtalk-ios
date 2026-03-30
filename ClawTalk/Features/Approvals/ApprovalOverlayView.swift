import SwiftUI

/// Overlay that shows pending exec approval banners.
/// Placed as an overlay on the root app view.
struct ApprovalOverlayView: View {
    var gatewayConnection: GatewayConnection

    var body: some View {
        VStack(spacing: 8) {
            ForEach(gatewayConnection.pendingApprovals) { approval in
                ApprovalBannerView(approval: approval) { id, decision in
                    Task {
                        try? await gatewayConnection.resolveApproval(id: id, decision: decision)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()
        }
        .padding(.top, 4)
        .animation(.spring(duration: 0.3), value: gatewayConnection.pendingApprovals.map(\.id))
    }
}
