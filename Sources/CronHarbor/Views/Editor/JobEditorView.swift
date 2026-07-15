import SwiftUI

struct JobEditorView: View {
    @Binding private var draft: JobDraft
    @State private var preset: SchedulePreset

    let onCancel: () -> Void
    let onSave: (JobDraft) -> Void

    init(
        draft: Binding<JobDraft>,
        onCancel: @escaping () -> Void,
        onSave: @escaping (JobDraft) -> Void
    ) {
        _draft = draft
        _preset = State(initialValue: SchedulePreset.detect(draft.wrappedValue.expression))
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelPageHeader(
                title: draft.id == nil ? "New Cron Job" : "Edit Cron Job",
                subtitle: "Changes stay staged until you apply",
                onBack: onCancel
            )
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    editorSection("JOB", symbol: "tag") {
                        TextField("Name", text: $draft.name, prompt: Text("Nightly Backup"))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("cronharbor.editor.name")

                        Toggle("Enabled", isOn: $draft.isEnabled)
                            .toggleStyle(.switch)
                    }

                    editorSection("SCHEDULE", symbol: "calendar.badge.clock") {
                        Picker("Runs", selection: $preset) {
                            ForEach(SchedulePreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .onChange(of: preset) { _, newValue in
                            if let expression = newValue.expression {
                                draft.expression = expression
                            }
                        }

                        TextField("Cron expression", text: $draft.expression)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("cronharbor.editor.schedule")
                            .onChange(of: draft.expression) { _, expression in
                                let detected = SchedulePreset.detect(expression)
                                if detected != preset { preset = detected }
                            }

                        HStack(spacing: 5) {
                            cronHint("min")
                            cronHint("hour")
                            cronHint("day")
                            cronHint("month")
                            cronHint("weekday")
                        }

                        Label(
                            CronExpressionFormatter.describe(draft.expression),
                            systemImage: "clock"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CronHarborStyle.accent)

                        Toggle("Run only on AC power", isOn: $draft.requiresACPower)
                            .toggleStyle(.switch)
                            .help("Uses macOS cron's @AppleNotOnBattery qualifier")
                    }

                    editorSection("COMMAND", symbol: "terminal") {
                        TextEditor(text: $draft.command)
                            .font(.system(.callout, design: .monospaced))
                            .frame(height: 76)
                            .scrollContentBackground(.hidden)
                            .padding(7)
                            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityIdentifier("cronharbor.editor.command")

                        Text("Shell syntax is preserved exactly. Run Now always asks for confirmation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let validationMessage = draft.validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityIdentifier("cronharbor.editor.validation")
                    }
                }
                .padding(13)
            }

            Divider()
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(draft.id == nil ? "Stage Job" : "Stage Changes") {
                    onSave(draft)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.validationMessage != nil)
                .accessibilityIdentifier("cronharbor.editor.stage")
            }
            .padding(12)
        }
        .accessibilityIdentifier("cronharbor.menu.editor")
    }

    private func editorSection<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(11)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 10))
    }

    private func cronHint(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }
}

private enum SchedulePreset: String, CaseIterable, Identifiable {
    case everyFiveMinutes
    case everyFifteenMinutes
    case hourly
    case dailyMorning
    case dailyNight
    case weekdays
    case weekly
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyFiveMinutes: "Every 5 minutes"
        case .everyFifteenMinutes: "Every 15 minutes"
        case .hourly: "Every hour"
        case .dailyMorning: "Every day at 9:00 AM"
        case .dailyNight: "Every day at 2:00 AM"
        case .weekdays: "Weekdays at 9:00 AM"
        case .weekly: "Every Sunday at 9:00 AM"
        case .custom: "Custom expression"
        }
    }

    var expression: String? {
        switch self {
        case .everyFiveMinutes: "*/5 * * * *"
        case .everyFifteenMinutes: "*/15 * * * *"
        case .hourly: "0 * * * *"
        case .dailyMorning: "0 9 * * *"
        case .dailyNight: "0 2 * * *"
        case .weekdays: "0 9 * * 1-5"
        case .weekly: "0 9 * * 0"
        case .custom: nil
        }
    }

    static func detect(_ expression: String) -> SchedulePreset {
        allCases.first(where: { $0.expression == expression }) ?? .custom
    }
}
