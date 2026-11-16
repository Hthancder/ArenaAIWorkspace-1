//
//  EndpointButton.swift
//  AIGate
//
//  Created by 秋星桥 on 2024/8/27.
//

import SwiftUI

struct EndpointButton: View {
    let endpoint: Configuration.Endpoint
    let onEdit: () -> Void

    @StateObject var configuration = Configuration.shared
    @StateObject var viewModel = Configuration.shared.viewModel

    var isActivated: Bool {
        viewModel.uiActivatedEndpoint == endpoint
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if isActivated {
                    configuration.activatedEndpointID = Configuration.noneActivated
                } else {
                    configuration.activatedEndpointID = endpoint.id
                }
                configuration.saveNow()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isActivated ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isActivated ? .accent : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(endpoint.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(endpoint.displayModel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Text(endpoint.url.absoluteString)
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                onEdit()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline)
                    .foregroundColor(.accent)
                    .padding(6)
            }
            .buttonStyle(.borderless)
        }
        .contextMenu {
            Button {
                if isActivated {
                    configuration.activatedEndpointID = Configuration.noneActivated
                } else {
                    configuration.activatedEndpointID = endpoint.id
                }
                configuration.saveNow()
            } label: {
                Label(isActivated ? "Deactivate" : "Activate", systemImage: isActivated ? "xmark.circle" : "checkmark.circle")
            }

            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                let copy = Configuration.Endpoint(
                    name: endpoint.name.isEmpty ? "" : "\(endpoint.name) Copy",
                    url: endpoint.url,
                    token: endpoint.token,
                    model: endpoint.model,
                    pathMode: endpoint.pathMode,
                    customHeaders: endpoint.customHeaders,
                    useStreaming: endpoint.useStreaming,
                    timeoutSeconds: endpoint.timeoutSeconds
                )
                configuration.add(copy, activateIfNone: false)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            Divider()

            Button {
                UIPasteboard.general.string = endpoint.url.absoluteString
            } label: {
                Label("Copy URL", systemImage: "link")
            }

            Button {
                UIPasteboard.general.string = endpoint.model
            } label: {
                Label("Copy Model", systemImage: "cpu")
            }

            if !endpoint.token.isEmpty {
                Button {
                    UIPasteboard.general.string = endpoint.token
                } label: {
                    Label("Copy Token", systemImage: "key")
                }
            }

            Divider()

            Button(role: .destructive) {
                configuration.remove(endpoint)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
