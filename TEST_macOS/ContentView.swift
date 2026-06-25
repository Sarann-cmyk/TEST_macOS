//
//  ContentView.swift
//  TEST_macOS
//
//  Created by Aleks Synelnyk on 25.06.2026.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var syncMonitor: CloudKitSyncMonitor

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TaskItem.createdAt, ascending: false)],
        animation: .default
    )
    private var tasks: FetchedResults<TaskItem>

    @State private var newTaskTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Нова задача", text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTask() }

                Button(action: addTask) {
                    Label("Додати", systemImage: "plus")
                }
                .disabled(trimmedTitle.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding()

            Divider()

            if tasks.isEmpty {
                ContentUnavailableView(
                    "Немає задач",
                    systemImage: "checklist",
                    description: Text("Задачі з iPhone з’являться тут після синхронізації.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(tasks) { task in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title ?? "Без назви")
                                if let createdAt = task.createdAt {
                                    Text(createdAt, formatter: itemFormatter)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button(role: .destructive) {
                                deleteTask(task)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .help("Видалити")
                        }
                    }
                    .onDelete(perform: deleteTasks)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .safeAreaInset(edge: .bottom) {
            Text(syncMonitor.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .task {
            await CloudKitTaskSync.shared.pullFromCloud(
                viewContext: viewContext,
                syncMonitor: syncMonitor
            )
            CloudKitTaskSync.shared.startPolling(
                viewContext: viewContext,
                syncMonitor: syncMonitor
            )
        }
    }

    private var trimmedTitle: String {
        newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addTask() {
        let title = trimmedTitle
        guard !title.isEmpty else { return }

        Task {
            do {
                try await CloudKitTaskSync.shared.createTask(title: title, viewContext: viewContext)
                newTaskTitle = ""
            } catch {
                syncMonitor.statusMessage = "Не вдалося створити: \(error.localizedDescription)"
            }
        }
    }

    private func deleteTask(_ task: TaskItem) {
        Task {
            do {
                try await CloudKitTaskSync.shared.deleteTask(task, viewContext: viewContext)
            } catch {
                syncMonitor.statusMessage = "Не вдалося видалити: \(error.localizedDescription)"
            }
        }
    }

    private func deleteTasks(offsets: IndexSet) {
        let toDelete = offsets.map { tasks[$0] }
        Task {
            for task in toDelete {
                do {
                    try await CloudKitTaskSync.shared.deleteTask(task, viewContext: viewContext)
                } catch {
                    syncMonitor.statusMessage = "Не вдалося видалити: \(error.localizedDescription)"
                }
            }
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(CloudKitSyncMonitor())
}
