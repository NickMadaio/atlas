import AtlasCore
import SwiftUI

struct ContextAssistantView: View {
    let context: AtlasLocalContext
    @Environment(\.atlasPalette) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var exchanges: [Exchange]

    init(context: AtlasLocalContext) {
        self.context = context
        _exchanges = State(initialValue: [Exchange(question: nil, answer: AtlasLocalAssistant.welcome(for: context))])
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contextHeader
                Divider().overlay(theme.divider)
                conversation
                questionComposer
            }
            .background(theme.canvas)
            .navigationTitle("Ask Atlas")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reset") { reset() }
                        .disabled(exchanges.count == 1)
                }
            }
        }
        .atlasAssistantSheet()
        .presentationBackground(theme.canvas)
    }

    private var contextHeader: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(theme.heroGradient)
                Image(systemName: "sparkles")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.scopeLabel)
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(theme.primary)
                Text(context.title)
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Label("Local only · nothing leaves this device", systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(theme.surface)
        .accessibilityElement(children: .combine)
    }

    private var conversation: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AtlasLocalAssistant.suggestions(for: context), id: \.self) { suggestion in
                            Button(suggestion) { submit(suggestion) }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(theme.primary)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 34)
                                .background(theme.tintSurface, in: Capsule())
                                .buttonStyle(.plain)
                                .contentShape(Capsule())
                        }
                    }
                }
                .accessibilityLabel("Suggested questions")

                ForEach(exchanges) { exchange in
                    if let question = exchange.question {
                        Text(question)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: 340, alignment: .leading)
                            .background(theme.primary, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    answerCard(exchange.answer)
                }
            }
            .padding(18)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func answerCard(_ answer: AtlasLocalAnswer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(theme.primary)
                Text(answer.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(theme.textPrimary)
            }
            Text(answer.body)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !answer.sources.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(answer.sources.prefix(6)) { source in
                            Label(source.sectionTitle, systemImage: "doc.text")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(theme.textSecondary)
                                .padding(.horizontal, 9)
                                .frame(minHeight: 28)
                                .background(theme.canvas, in: Capsule())
                                .overlay { Capsule().stroke(theme.divider, lineWidth: 1) }
                                .accessibilityLabel("Source: \(source.documentTitle), \(source.sectionTitle)")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .atlasCard(padding: 16, radius: 18)
    }

    private var questionComposer: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask about this context", text: $question, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .foregroundStyle(theme.textPrimary)
                    .onSubmit { submit(question) }
                    .onChange(of: question) { _, value in
                        if value.count > AtlasLocalAssistant.maximumQuestionLength {
                            question = String(value.prefix(AtlasLocalAssistant.maximumQuestionLength))
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(theme.canvas, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 13).stroke(theme.divider, lineWidth: 1) }

                Button { submit(question) } label: {
                    Image(systemName: "arrow.up")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(theme.primary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                .accessibilityLabel("Ask Atlas")
            }
            Text("Extractive local help · verify important details in the source note")
                .font(.system(size: 9))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(14)
        .background(theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(theme.divider).frame(height: 1) }
    }

    private func submit(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let bounded = String(trimmed.prefix(AtlasLocalAssistant.maximumQuestionLength))
        exchanges.append(Exchange(question: bounded, answer: AtlasLocalAssistant.answer(bounded, in: context)))
        if exchanges.count > 7 { exchanges.removeFirst(exchanges.count - 7) }
        question = ""
    }

    private func reset() {
        question = ""
        exchanges = [Exchange(question: nil, answer: AtlasLocalAssistant.welcome(for: context))]
    }

    private struct Exchange: Identifiable {
        let id = UUID()
        let question: String?
        let answer: AtlasLocalAnswer
    }
}

private extension View {
    @ViewBuilder func atlasAssistantSheet() -> some View {
        #if os(macOS)
        frame(minWidth: 500, idealWidth: 540, minHeight: 620, idealHeight: 680)
        #else
        presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        #endif
    }
}
