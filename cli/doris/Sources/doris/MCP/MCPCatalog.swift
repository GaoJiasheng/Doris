import Foundation
import DorisIPC

/// Everything an agent reads to learn Doris: the server instructions (sent
/// once, at connection), each tool's description and parameters (sent to the
/// model by every client — so the rules that matter live here too, not only
/// in the instructions), and a few ready-made prompts that clients show as
/// commands (`/mcp__doris__today` in Claude Code).
///
/// Kept short on purpose: tool descriptions ride along in every
/// conversation, and a long manual costs context and buries the rules.
enum MCPCatalog {
    static let instructions = """
    Doris is the user's to-do list and notes app — in their Mac's menu bar and on their iPhone, synced through their own iCloud. These tools read and change it.

    Use Doris when the user wants to remember, plan, track or tick off things to do ("add a to-do", "remind me to…", "what's left today", "记一下", "加个待办"), or to keep a visible checklist of steps while you work through them.

    How Doris works:
    - A task has a title, optional notes, optional checklist items and an optional due day (a date, never a time).
    - "Today" in Doris means overdue, due today, and pinned — list_tasks with view "today".
    - Every result starts with today's date in the user's time zone; use it to work out "tomorrow" or "Friday".

    Good practice:
    - When the user mentions one of their tasks by name ("the gym task", "「…」这个任务"), it's in Doris: find it with list_tasks before answering.
    - Breaking a task into steps means adding them to that task (update_task, add_items) — not just listing them in your reply.
    - Search with list_tasks before create_task, and update an existing task instead of adding a duplicate.
    - Several steps toward one goal → one task with `items`, not several tasks.
    - Write titles and items in the language the user is using with you, short and concrete.
    - Ask before changing more than three tasks at once, unless the user asked for exactly that.
    - Nothing can be deleted through these tools. archive_task hides a task, and the user can restore it.
    """

    // MARK: - Tools

    static func tools() -> [[String: Any]] {
        [
            tool(.listTasks, "List tasks",
                 "List the user's tasks in Doris. `view`: today = overdue + due today + pinned (what \"today\" means in Doris); upcoming = due after today; open = everything not done (default); done = recently completed; all. `query` matches title, notes and items. Returns each task's id for the other tools.",
                 properties: [
                    "view": ["type": "string", "enum": ["today", "upcoming", "open", "done", "all"],
                             "description": "Which tasks. Default: open."],
                    "query": ["type": "string", "description": "Words to look for; a task matches when all of them appear in its title, notes or items."],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 100, "description": "At most this many (default 30)."],
                 ]),
            tool(.getTask, "Read a task",
                 "Read one task in full: notes, numbered checklist items (the numbers check_item takes), due day, pinned and done state.",
                 properties: ["id": idProperty], required: ["id"]),
            tool(.createTask, "Create a task",
                 "Add a task to Doris. Search with list_tasks first and update an existing task rather than duplicating it. Put the steps of one goal in `items` — they become a checklist inside this one task. Write in the user's language.",
                 properties: [
                    "title": ["type": "string", "description": "Short and concrete, e.g. \"Reply to Alex about the contract\"."],
                    "notes": ["type": "string", "description": "Optional details."],
                    "items": ["type": "array", "items": ["type": "string"], "description": "Checklist steps, in order."],
                    "due": dueProperty(clearable: false),
                    "pinned": ["type": "boolean", "description": "Pin to the top of the user's Today. Only if the user asks or it's clearly urgent."],
                 ], required: ["title"]),
            tool(.updateTask, "Update a task",
                 "Change a task — e.g. break it into steps with `add_items`. Only the fields you pass change, and nothing is removed. To tick a step use check_item; to finish the task use complete_task.",
                 properties: [
                    "id": idProperty,
                    "title": ["type": "string", "description": "New title."],
                    "append_notes": ["type": "string", "description": "Text added to the end of the notes."],
                    "add_items": ["type": "array", "items": ["type": "string"], "description": "Checklist steps added at the end."],
                    "due": dueProperty(clearable: true),
                    "pinned": ["type": "boolean", "description": "Pin to (true) or unpin from (false) the user's Today."],
                 ], required: ["id"]),
            tool(.checkItem, "Tick a checklist item",
                 "Tick one checklist item (or untick it with done=false), by its number from get_task or create_task. Ticking the last open item completes the task. Use it to show progress as you work through a checklist.",
                 properties: [
                    "id": idProperty,
                    "item": ["type": "integer", "minimum": 1, "description": "The item's number, starting at 1."],
                    "done": ["type": "boolean", "description": "Default true."],
                 ], required: ["id", "item"]),
            tool(.completeTask, "Complete a task",
                 "Mark a whole task done, or not done with done=false. For a single checklist step, use check_item.",
                 properties: [
                    "id": idProperty,
                    "done": ["type": "boolean", "description": "Default true."],
                 ], required: ["id"]),
            tool(.archiveTask, "Archive a task",
                 "Take a task off the user's lists. It is archived, not deleted — the user can restore it, and Doris has no delete. Only when the user asks to remove or clear a task.",
                 properties: ["id": idProperty], required: ["id"]),
        ]
    }

    private static let idProperty: [String: Any] = [
        "type": "string", "description": "The task's id from list_tasks (the first 8 characters are enough).",
    ]

    private static func dueProperty(clearable: Bool) -> [String: Any] {
        ["type": "string",
         "description": clearable
            ? "Due day: YYYY-MM-DD, today, tomorrow, or none to clear it. In the user's time zone."
            : "Due day: YYYY-MM-DD, today or tomorrow, in the user's time zone. Leave out if there's no deadline."]
    }

    private static func tool(_ t: AgentTool, _ title: String, _ description: String,
                             properties: [String: Any], required: [String] = []) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        let readOnly = !t.writes
        return [
            "name": t.rawValue,
            "title": title,
            "description": description,
            "inputSchema": schema,
            "annotations": [
                "readOnlyHint": readOnly,
                // Archive is reversible, so nothing here is destructive.
                "destructiveHint": false,
                "idempotentHint": readOnly || t == .completeTask || t == .checkItem || t == .archiveTask,
                "openWorldHint": false,
            ],
        ]
    }

    // MARK: - Prompts

    struct Prompt {
        let name: String
        let title: String
        let description: String
        let arguments: [[String: Any]]
        let text: ([String: String]) -> String
    }

    static let prompts: [Prompt] = [
        Prompt(name: "today", title: "Today in Doris",
               description: "Go over what's on the user's plate today and suggest an order.",
               arguments: [],
               text: { _ in
                   "Look at my tasks for today in Doris (list_tasks, view \"today\") and help me plan the day. Be brief: what's overdue, what's due today, what's pinned — then suggest an order to tackle them. Don't change anything unless I ask."
               }),
        Prompt(name: "plan", title: "Plan it in Doris",
               description: "Turn a goal into one Doris task with checklist steps.",
               arguments: [["name": "goal", "description": "What to plan. Leave empty for what we're working on.", "required": false]],
               text: { args in
                   let goal = args["goal"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                   let what = (goal?.isEmpty == false) ? "\"\(goal!)\"" : "what we're working on right now"
                   return "Turn \(what) into a task in Doris: a short title, the steps as checklist items, and a due day only if one is clear. First check list_tasks for an existing task about it and add to that instead. Then show me the result."
               }),
        Prompt(name: "wrapup", title: "Wrap up into Doris",
               description: "Record this conversation's follow-ups as Doris tasks.",
               arguments: [],
               text: { _ in
                   "We're wrapping up. Record the follow-ups from this conversation in Doris: one task per separate piece of follow-up work, with its steps as checklist items, and tick off steps we've already finished. If it comes to more than three tasks, show me the list before creating them."
               }),
    ]
}
