import SwiftUI

/// Shows which database columns the widget uses, with a picker to override
/// each guess.
struct NookNotionMappingSection: View {
    var service: NookNotionTodoService
    var schema: NotionDataSource

    private static let doneTypes = ["status", "select", "checkbox"]
    private static let filterTypes = ["select", "multi_select"]

    private var lang: LanguageManager { .shared }
    private var mapping: NotionTodoMapping { service.mapping }

    var body: some View {
        Section(lang.t("nook.todo.notion.mapping.section")) {
            LabeledContent(lang.t("nook.todo.notion.mapping.title")) {
                Text(schema.properties.values.first { $0.type == "title" }?.name ?? lang.t("nook.todo.notion.mapping.none"))
                    .foregroundStyle(.secondary)
            }

            propertyPicker(
                "nook.todo.notion.mapping.done",
                types: Self.doneTypes,
                showsType: true,
                selection: Binding(get: { mapping.donePropertyID }, set: { service.setDoneProperty(id: $0) })
            )
            doneDetail

            propertyPicker("nook.todo.notion.mapping.due", types: ["date"], selection: Binding(
                get: { mapping.duePropertyID },
                set: { id in service.updateMapping { $0.duePropertyID = id } }
            ))
            propertyPicker("nook.todo.notion.mapping.priority", types: ["select"], selection: Binding(
                get: { mapping.priorityPropertyID },
                set: { id in service.updateMapping { $0.priorityPropertyID = id } }
            ))
            propertyPicker("nook.todo.notion.mapping.notes", types: ["rich_text"], selection: Binding(
                get: { mapping.notesPropertyID },
                set: { id in service.updateMapping { $0.notesPropertyID = id } }
            ))
            propertyPicker("nook.todo.notion.mapping.filter", types: Self.filterTypes, selection: Binding(
                get: { mapping.filterPropertyID },
                set: { id in
                    service.updateMapping {
                        $0.filterPropertyID = id
                        $0.filterValues = []
                    }
                }
            ))
            filterValues

            if case .needsAttention(let issue) = service.state {
                Label(lang.t("nook.todo.notion.issue.\(issue.rawValue)"), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var doneDetail: some View {
        if mapping.doneKind == .select, let property = schema.property(id: mapping.donePropertyID) {
            Picker(lang.t("nook.todo.notion.mapping.doneValue"), selection: Binding(
                get: { mapping.doneOptionName },
                set: { name in service.updateMapping { $0.doneOptionName = name } }
            )) {
                Text(lang.t("nook.todo.notion.mapping.none")).tag(String?.none)
                ForEach(property.options, id: \.name) { option in
                    Text(option.name).tag(Optional(option.name))
                }
            }
        } else if mapping.doneKind == .status {
            Text(lang.t("nook.todo.notion.mapping.doneStatusNote"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var filterValues: some View {
        if let property = schema.property(id: mapping.filterPropertyID) {
            ForEach(property.options, id: \.name) { option in
                Toggle(option.name, isOn: Binding(
                    get: { mapping.filterValues.contains(option.name) },
                    set: { isOn in
                        service.updateMapping { mapping in
                            mapping.filterValues.removeAll { $0 == option.name }
                            if isOn { mapping.filterValues.append(option.name) }
                        }
                    }
                ))
            }
            Text(lang.t("nook.todo.notion.mapping.filter.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// A picker over the columns of the given types. A saved column that no
    /// longer exists reads as "None", and the section shows why below.
    private func propertyPicker(
        _ titleKey: String,
        types: [String],
        showsType: Bool = false,
        selection: Binding<String?>
    ) -> some View {
        let candidates = schema.sortedProperties.filter { types.contains($0.type) && !$0.id.isEmpty }
        let known = Set(candidates.map(\.id))
        let shown = Binding<String?>(
            get: { selection.wrappedValue.flatMap { known.contains($0) ? $0 : nil } },
            set: { selection.wrappedValue = $0 }
        )
        return Picker(lang.t(titleKey), selection: shown) {
            Text(lang.t("nook.todo.notion.mapping.none")).tag(String?.none)
            ForEach(candidates, id: \.id) { property in
                Text(showsType ? "\(property.name) (\(lang.t("nook.todo.notion.type.\(property.type)")))" : property.name)
                    .tag(Optional(property.id))
            }
        }
    }
}
