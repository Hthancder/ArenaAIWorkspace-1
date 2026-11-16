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
        viewModel.uiActivatedEndpoint?.id == endpoint.id
    }

    var models: [String] {
        endpoint.normalizedModels
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                            .foregroundColor(isActivated ? viewModel.uiAccentColor : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(endpoint.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                if models.count > 1 {
                                    Text("\(models.count) models")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(viewModel.uiAccentColor.opacity(0.14))
                                        .foregroundColor(viewModel.uiAccentColor)
                                        .cornerRadius(6)
                                }
                            }
                            Text(endpoint.displayModel)
                                .font(.caption)
                                .foregroundColor(isActivated ? viewModel.uiAccentColor : .secondary)
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
                        .foregroundColor(viewModel.uiAccentColor)
                        .padding(6)
                }
                .buttonStyle(.borderless)
            }

            if models.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(models, id: \.self) { m in
                            let selected = isActivated && (endpoint.model == m)
                            let activeInProvider = (endpoint.model == m)
                            Button {
                                configuration.switchModel(forEndpoint: endpoint.id, model: m, activateEndpoint: true)
                            } label: {
                                HStack(spacing: 4) {
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    Text(m)
                                        .font(.system(.caption2, design: .monospaced))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    selected
                                        ? viewModel.uiAccentColor.opacity(0.22)
                                        : (activeInProvider ? Color.secondary.opacity(0.18) : Color.secondary.opacity(0.10))
                                )
                                .foregroundColor(selected ? viewModel.uiAccentColor : .primary)
                                .cornerRadius(7)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.leading, 28)
                }
            }
        }
        .padding(.vertical, 2)
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

            if models.count > 1 {
                Menu {
                    ForEach(models, id: \.self) { m in
                        Button {
                            configuration.switchModel(forEndpoint: endpoint.id, model: m, activateEndpoint: true)
                        } label: {
                            if isActivated && endpoint.model == m {
                                Label(m, systemImage: "checkmark")
                            } else {
                                Text(m)
                            }
                        }
                    }
                } label: {
                    Label("Switch Model", systemImage: "cpu")
                }
            }

            Button {
                onEdit()
            } label: {
                Label("Edit Provider & Models", systemImage: "pencil")
            }

            Button {
                let copy = Configuration.Endpoint(
                    name: endpoint.name.isEmpty ? "" : "\(endpoint.name) Copy",
                    url: endpoint.url,
                    token: endpoint.token,
                    model: endpoint.model,
                    models: endpoint.normalizedModels,
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
                Label("Copy Active Model", systemImage: "cpu")
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
