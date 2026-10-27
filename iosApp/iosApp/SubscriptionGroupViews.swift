// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI

struct SubscriptionGroupFilter: View {
  @EnvironmentObject private var groups: SubscriptionGroups
  @Binding var selection: UUID?
  @State private var choosing = false
  var body: some View {
    HStack {
      Button {
        choosing = true
      } label: {
        Label(
          groups.groups.first { $0.id == selection }?.name ?? String(localized: "All subscriptions"),
          systemImage: "line.3.horizontal.decrease.circle"
        )
        .lineLimit(1).frame(minHeight: 44).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityIdentifier("subscriptionGroupFilter")
      Spacer()
      Button {
        NotificationCenter.default.post(name: .driftLoomManageGroups, object: nil)
      } label: {
        Image(systemName: "folder.badge.gearshape").frame(width: 44, height: 44)
      }
      .accessibilityLabel("Manage subscription groups").accessibilityIdentifier(
        "manageSubscriptionGroups")
    }.padding(.horizontal, 12)
      .confirmationDialog("Subscription group", isPresented: $choosing, titleVisibility: .visible) {
        Button("All subscriptions") { selection = nil }.accessibilityIdentifier("selectGroup-all")
        ForEach(groups.groups) { group in
          Button(group.name) { selection = group.id }.accessibilityIdentifier(
            "selectGroup-" + group.id.uuidString)
        }
        Button("Cancel", role: .cancel) {}
      }
      .onChange(of: groups.groups.map(\.id)) { ids in
        if let id = selection, !ids.contains(id) { selection = nil }
      }
  }
}

private struct GroupEditorTarget: Identifiable {
  let id = UUID()
  var group: SubscriptionGroup?
}

struct SubscriptionGroupsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var groups: SubscriptionGroups
  @EnvironmentObject private var library: LibraryStore
  @State private var editor: GroupEditorTarget?
  @State private var deleting: [UUID] = []
  @State private var editMode = EditMode.inactive
  var body: some View {
    AppNavigation {
      if let editor {
        SubscriptionGroupEditor(group: editor.group, onClose: { self.editor = nil }).id(editor.id)
      } else {
        VStack(spacing: 0) {
          HStack {
            Button("Done") { dismiss() }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier(
              "closeSubscriptionGroups")
            Spacer()
            Text("Subscription groups").font(.headline).accessibilityIdentifier(
              "subscriptionGroupsTitle")
            Spacer()
            EditButton().frame(minWidth: 44, minHeight: 44).disabled(!groups.isWritable)
          }.padding(.horizontal, 12)
          List {
            Section {
              Button("New subscription group") { editor = GroupEditorTarget() }
                .disabled(!groups.isWritable).accessibilityIdentifier("createSubscriptionGroup")
              Text(
                "Group channels to filter your subscriptions and What's new. Removing a group keeps your subscriptions."
              )
              .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Groups") {
              ForEach(groups.groups) { group in
                Button {
                  editor = GroupEditorTarget(group: group)
                } label: {
                  HStack {
                    Label(group.name, systemImage: "folder").foregroundStyle(.primary)
                    Spacer()
                    Text(
                      "\(groups.channelIDs(for: group.id, subscribed: library.subscriptions.map { $0.item.contentID }).count)"
                    )
                    .foregroundStyle(.secondary)
                  }.padding(.vertical, 5)
                }.accessibilityIdentifier("editGroup-" + group.id.uuidString)
              }
              .onDelete { offsets in deleting = offsets.map { groups.groups[$0].id } }
              .onMove { groups.move(from: $0, to: $1) }
              .disabled(!groups.isWritable)
            }
          }
        }
        .navigationBarHidden(true)
        .environment(\.editMode, $editMode)
        .confirmationDialog(
          "Remove selected groups?",
          isPresented: Binding(get: { !deleting.isEmpty }, set: { if !$0 { deleting = [] } }),
          titleVisibility: .visible
        ) {
          Button("Remove groups", role: .destructive) {
            for id in deleting { groups.remove(id) }
            deleting = []
          }
          Button("Cancel", role: .cancel) { deleting = [] }
        } message: {
          Text("Your channels will stay subscribed.")
        }
      }
    }
  }
}

private struct SubscriptionGroupEditor: View {
  let onClose: () -> Void
  @EnvironmentObject private var groups: SubscriptionGroups
  @EnvironmentObject private var library: LibraryStore
  private let id: UUID
  @State private var name: String
  @State private var members: Set<String>
  @State private var error: String?
  @FocusState private var nameFocused: Bool
  init(group: SubscriptionGroup?, onClose: @escaping () -> Void) {
    self.onClose = onClose
    id = group?.id ?? UUID()
    _name = State(initialValue: group?.name ?? "")
    _members = State(initialValue: Set(group?.channelIDs ?? []))
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button("Cancel") { onClose() }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("cancelGroupEdit")
        Spacer()
        Text("Edit group").font(.headline)
        Spacer()
        Button("Save") {
          if groups.upsert(id: id, name: name, channelIDs: Array(members)) {
            onClose()
          } else {
            error = groups.error ?? String(localized: "Couldn't save this group.")
          }
        }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("saveSubscriptionGroup")
          .disabled(
            !groups.isWritable || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || name.count > 100)
      }.padding(.horizontal, 12)
      Form {
        Section("Group name") {
          TextField("Name", text: $name).accessibilityIdentifier("subscriptionGroupName")
            .focused($nameFocused).submitLabel(.done).onSubmit { nameFocused = false }
        }
        Section("Channels") {
          if library.subscriptions.isEmpty {
            Text("Subscribe to channels to add them to a group.").foregroundStyle(.secondary)
          }
          ForEach(library.subscriptions) { record in
            Button {
              nameFocused = false
              if members.contains(record.item.contentID) {
                members.remove(record.item.contentID)
              } else {
                members.insert(record.item.contentID)
              }
            } label: {
              HStack {
                Text(record.item.title).foregroundStyle(.primary)
                Spacer()
                Image(
                  systemName: members.contains(record.item.contentID)
                    ? "checkmark.circle.fill" : "circle")
              }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("groupMember-" + record.item.contentID)
              .accessibilityValue(
                members.contains(record.item.contentID) ? "Selected" : "Not selected")
          }
        }
        if let error { Text(error).font(.footnote).foregroundColor(.red) }
      }
    }
    .navigationBarHidden(true)
  }
}
