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

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Task.createdAt, ascending: false)],
        animation: .default)
    private var tasks: FetchedResults<Task>

    @State private var newTaskTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("New task...", text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)
                Button("Add", action: addTask)
                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            Divider()

            if tasks.isEmpty {
                ContentUnavailableView("No tasks", systemImage: "checkmark.circle")
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(tasks) { task in
                        Text(task.title ?? "")
                    }
                    .onDelete(perform: deleteTasks)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let task = Task(context: viewContext)
        task.title = title
        task.createdAt = Date()
        try? viewContext.save()
        newTaskTitle = ""
    }

    private func deleteTasks(offsets: IndexSet) {
        offsets.map { tasks[$0] }.forEach(viewContext.delete)
        try? viewContext.save()
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
