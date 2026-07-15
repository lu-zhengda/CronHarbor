import SwiftUI

struct JobEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: JobDraft
    @State private var preset: SchedulePreset

    let onSave: (JobDraft) -> Void

    init(draft: JobDraft, onSave: @escaping (JobDraft) -> Void) {
        _draft = State(initialValue: draft)
        _preset = State(initialValue: SchedulePreset.detect(draft.expression))
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.id == nil ? "New Cron Job" : "Edit Cron Job")
                        .font(.title2.weight(.semibold))
                    Text("Changes remain staged until you review and apply them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(22)

            Divider()

            Form {
                Section("Job") {
                    TextField("Name", text: $draft.name, prompt: Text("Nightly Backup"))
                    Toggle("Enabled", isOn: $draft.isEnabled)
                }

                Section("Schedule") {
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

                    HStack(spacing: 12) {
                        FieldHint(value: "*", label: "minute")
                        FieldHint(value: "*", label: "hour")
                        FieldHint(value: "*", label: "day")
                        FieldHint(value: "*", label: "month")
                        FieldHint(value: "*", label: "weekday")
                    }

                    Text(CronExpressionFormatter.describe(draft.expression))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(CronHarborStyle.accent)

                    Toggle("Run only on AC power", isOn: $draft.requiresACPower)
                        .help("Uses macOS cron's @AppleNotOnBattery qualifier.")
                }

                Section("Command") {
                    TextEditor(text: $draft.command)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 88)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))

                    Text("CronHarbor preserves shell syntax exactly. Run Now asks you to confirm the command and explains its cron-like execution context.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let validationMessage = draft.validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(draft.id == nil ? "Stage Job" : "Stage Changes") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.validationMessage != nil)
            }
            .padding(18)
        }
        .frame(width: 590, height: 620)
    }
}

private struct FieldHint: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
