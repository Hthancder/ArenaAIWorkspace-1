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

    @ObservedObject var configuration = Configuration.shared
    @ObservedObject var viewModel = Configuration.shared.viewModel

    var isActivated: Bool {
        viewModel.uiActivatedEndpoint?.id == endpoint.id
    }

    private var savedModels: [String] {
        endpoint.effectiveModels
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    if isActivated {
                        configuration.activatedEndpointID = Configuration.noneActivated
                        configuration.saveNow()
                    } else {
                        configuration.activateEndpoint(id: endpoint.id)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isActivated ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isActivated ? .accent : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(endpoint.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                if savedModels.count > 1 {
                                    Text("\(savedModels.count) models")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.accent.opacity(0.14))
                                        .foregroundColor(.accent)
                                        .cornerRadius(5)
                                }
                            }
                            Text(endpoint.displayModel)
                                .font(.caption)
                                .foregroundColor(isActivated ? .accent : .secondary)
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

            if savedModels.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(savedModels, id: \.self) { m in
                            let isSelected = isActivated && endpoint.model == m
                            let isDefaultForProvider = !isActivated && endpoint.model == m
                            Button {
                                configuration.activateEndpoint(id: endpoint.id, model: m)
                            } label: {
                                HStack(spacing: 4) {
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    Text(m)
                                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .monospaced))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    isSelected
                                        ? Color.accent.opacity(0.22)
                                        : (isDefaultForProvider ? Color.secondary.opacity(0.16) : Color.secondary.opacity(0.09))
                                )
                                .foregroundColor(isSelected ? .accent : .primary)
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
                    configuration.saveNow()
                } else {
                    configuration.activateEndpoint(id: endpoint.id)
                }
            } label: {
                Label(isActivated ? "Deactivate" : "Activate", systemImage: isActivated ? "xmark.circle" : "checkmark.circle")
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
                    models: endpoint.effectiveModels,
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
