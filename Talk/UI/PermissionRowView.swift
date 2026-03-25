//
//  PermissionRowView.swift
//  Talk
//
//  通用权限状态行
//

import SwiftUI

struct PermissionRowView: View {
    let permission: AppPermission
    let isGranted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: permission.iconName)
                    .font(.system(size: 32))
                    .foregroundStyle(iconColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(permission.title)
                        .font(.headline)
                    Text(permission.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.green)
                } else {
                    Button(actionTitle, action: action)
                        .controlSize(.small)
                }
            }

            if let restartHint = permission.restartHint, !isGranted {
                Text(restartHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 44)
            }
        }
        .padding(4)
    }

    private var iconColor: Color {
        switch permission {
        case .microphone:
            return .blue
        case .inputMonitoring:
            return .indigo
        case .accessibility:
            return .orange
        }
    }
}
