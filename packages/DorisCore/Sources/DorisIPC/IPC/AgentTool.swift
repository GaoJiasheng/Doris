import Foundation

/// The tools `doris mcp` offers agents. The CLI describes them (see its
/// MCP catalog); the app carries them out (`AgentToolRunner`). Sharing the
/// names keeps the two from drifting apart.
public enum AgentTool: String, CaseIterable, Sendable {
    case listTasks = "list_tasks"
    case getTask = "get_task"
    case createTask = "create_task"
    case updateTask = "update_task"
    case checkItem = "check_item"
    case completeTask = "complete_task"
    case archiveTask = "archive_task"

    /// Changes the user's data — refused when agents are set to read-only.
    public var writes: Bool {
        switch self {
        case .listTasks, .getTask: return false
        default: return true
        }
    }
}
