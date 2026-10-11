@testable import Keyveil

// Real menu captures.
//
// Recorded from a live macOS session by walking each application's AX menu bar
// with the same traversal Keyveil uses, so these tests describe the data the
// overlay is actually handed rather than a hand-written approximation.
//
// Captured shortcut counts: Finder 112, Safari 111, Preview 104, TextEdit 77,
// Calendar 62. The window arrangement block and the global commands are identical
// in all five.
//
// The captures keep repeated titles on purpose: Finder really does offer "Eject"
// three times and "Name" twice in one menu, which is what forces shortcut
// identity to include a positional component.
enum CapturedAppMenus {
    struct App {
        let name: String
        let groups: [String: [String]]
    }

    static let all: [App] = [
        App(name: "Calendar", groups: [
            "Calendar": ["Settings…", "Hide Calendar", "Hide Others", "Quit Calendar", "Quit and Keep Windows"],
            "File": ["New Event or Reminder", "New Calendar", "New Calendar Subscription…", "Close", "Close All", "Print…"],
            "Edit": ["Undo Deadline Change", "Redo", "Cut", "Copy", "Paste", "Select All", "Duplicate", "Edit Reminder", "Mark as Completed", "Get Info", "Show Inspector", "Search", "Show Spelling and Grammar", "Start Dictation", "Emoji & Symbols"],
            "View": ["By Day", "By Week", "By Month", "By Year", "Next", "Previous", "Go to Today", "Go to Date…", "Go to Next Occurrence", "Go to Previous Occurrence", "Zoom In", "Zoom Out", "Show All Tabs", "Refresh Calendars", "Enter Full Screen"],
            "Window": ["Minimise", "Minimise All", "Fill", "Centre", "Left", "Right", "Top", "Bottom", "Left & Right", "Left & Quarters", "Right & Left", "Right & Quarters", "Top & Bottom", "Top & Quarters", "Bottom & Top", "Bottom & Quarters", "Return to Previous Size", "Calendar", "Show Previous Tab", "Show Next Tab", "Availability Panel"],
        ]),
        App(name: "Finder", groups: [
            "Finder": ["Settings…", "Empty Bin…", "Empty Bin", "Hide Finder", "Hide Others"],
            "File": ["New Finder Window", "New Folder", "New Folder with Selection", "New Tab", "Open", "Open in New Tab", "Open in New Window and Close", "Close Window", "Close All", "Get Info", "Show Inspector", "Get Summary Info", "Duplicate", "Duplicate Exactly", "Make Alias", "Quick Look “Keyveil”", "Slideshow “Keyveil”", "Show Original", "Add to Sidebar", "Add to Dock", "Move to Bin", "Delete Immediately…", "Eject", "Eject", "Eject", "Print"],
            "Edit": ["Undo Rename", "Redo", "Cut", "Copy", "Copy “Keyveil” as Pathname", "Copy as Link", "Paste Item", "Move Item Here", "Paste Item Exactly", "Select All", "Deselect All", "Search", "Search by Name…", "Start Dictation", "Emoji & Symbols"],
            "View": ["as Icons", "as List", "as Columns", "as Gallery", "Use Groups", "Name", "Kind", "Date Last Opened", "Date Added", "Date Modified", "Size", "Tags", "Name", "Kind", "Date Modified", "Size", "Tags", "Show Tab Bar", "Show All Tabs", "Hide Sidebar", "Show Preview", "Hide Toolbar", "Hide Path Bar", "Hide Status Bar", "Show View Options", "Enter Full Screen"],
            "Go": ["Back", "Forward", "Enclosing Folder", "Enclosing Folder", "Enclosing Folder in New Window", "Select Startup Disk", "Recents", "Documents", "Desktop", "Downloads", "Home", "Computer", "AirDrop", "Network", "iCloud Drive", "Shared", "Applications", "Utilities", "Go to Folder…", "Connect to Server…"],
            "Window": ["Minimise", "Minimise All", "Fill", "Centre", "Left", "Right", "Top", "Bottom", "Left & Right", "Left & Quarters", "Right & Left", "Right & Quarters", "Top & Bottom", "Top & Quarters", "Bottom & Top", "Bottom & Quarters", "Return to Previous Size", "Cycle Through Windows", "Show Previous Tab", "Show Next Tab"],
        ]),
        App(name: "Preview", groups: [
            "Preview": ["Settings…", "Hide Preview", "Hide Others", "Quit Preview", "Quit and Keep Windows"],
            "File": ["New from Clipboard", "Open…", "Close Window", "Close All", "Close Selected PDF Document", "Save", "Save As…", "Duplicate", "Print…"],
            "Edit": ["Undo", "Redo", "Cut", "Copy", "Paste", "Select All", "Invert Selection", "Move Selected PDF Document to Bin", "Find…", "Find Next", "Find Previous", "Use Selection for Find", "Jump to Selection", "Show Spelling and Grammar", "Check Document Now", "Start Dictation", "Emoji & Symbols"],
            "View": ["Show All Tabs", "Hide Sidebar", "Thumbnails", "Table of Contents", "Highlights and Notes", "Bookmarks", "Contact Sheet", "Continuous Scroll", "Single Page", "Two Pages", "Show Image Background", "Actual Size", "Actual Size on All", "Zoom to Fit", "Zoom All to Fit", "Zoom In", "Zoom All In", "Zoom Out", "Zoom All Out", "Zoom to Selection", "Show Markup Toolbar", "Show Toolbar", "Slideshow", "Enter Full Screen"],
            "Go": ["Up", "Previous Document", "Down", "Next Document", "Previous Item", "Next Item", "Go to Page…", "Back", "Forward"],
            "Tools": ["Show Inspector", "Show Magnifier", "Move", "Rotate", "Scale", "Highlight Text", "Underline Text", "Strike Through Text", "Rectangle", "Oval", "Line", "Arrow", "Text", "Loupe", "Note", "Add Bookmark", "Rotate Left", "Rotate Right", "Crop", "Remove Background"],
            "Window": ["Minimise", "Minimise All", "Fill", "Centre", "Left", "Right", "Top", "Bottom", "Left & Right", "Left & Quarters", "Right & Left", "Right & Quarters", "Top & Bottom", "Top & Quarters", "Bottom & Top", "Bottom & Quarters", "Return to Previous Size", "Show Previous Tab", "Show Next Tab"],
            "Help": ["Preview Help"],
        ]),
        App(name: "Safari", groups: [
            "Safari": ["Settings…", "Hide Safari", "Hide Others", "Quit Safari", "Quit and Keep Windows"],
            "File": ["New Window", "New Private Window", "New Tab", "New Tab at End", "New Empty Tab Group", "Open File…", "Open Location…", "Close Window", "Close All Windows", "Close Tab", "Close Other Tabs", "Delete Tab Group", "Save As…", "Save As…"],
            "Edit": ["Undo Close Tab", "Redo", "Cut", "Copy", "Copy Search Terms", "Paste", "Paste and Match Style", "Select All", "AutoFill Form", "Bing Search…", "Find…", "Find Next", "Find Previous", "Hide Find Banner", "Use Selection for Find", "Jump to Selection", "Send a request to 2FAS", "Send a request to 2FAS", "Save to Notion", "Open Obsidian Clipper", "Quick clip", "Toggle highlighter mode", "Toggle reading view", "Show Spelling and Grammar", "Check Document Now", "Start Dictation", "Emoji & Symbols"],
            "View": ["Show Favourites Bar", "Show Status Bar", "Show Sidebar", "Show Bookmarks Sidebar", "Show Reading List Sidebar", "Enter Video Viewer", "Show Tab Overview", "Show Downloads", "Stop", "Reload Page", "Reload Page From Origin", "Actual Size", "Zoom In", "Make Text Bigger", "Zoom Out", "Make Text Smaller", "Enter Full Screen"],
            "History": ["Show All History", "Back", "Forward", "Home", "Return to Search Results", "Reopen Last Closed Tab"],
            "Bookmarks": ["Edit Bookmarks", "Add Bookmark…", "Add to Reading List", "Apple", "iCloud", "百度", "搜狗", "360搜索", "必应", "百度百科", "QQ空间", "新浪微博"],
            "Develop": ["Enter Responsive Design Mode", "Show Web Inspector", "Connect Web Inspector", "Show JavaScript Console", "Show Page Source", "Show Page Resources", "Start Timeline Recording", "Start Element Selection", "Empty Caches"],
            "Window": ["Minimise", "Minimise All", "Fill", "Centre", "Left", "Right", "Top", "Bottom", "Left & Right", "Left & Quarters", "Right & Left", "Right & Quarters", "Top & Bottom", "Top & Quarters", "Bottom & Top", "Bottom & Quarters", "Return to Previous Size", "Show Previous Tab", "Show Next Tab", "Go To Previous Tab Group", "Go To Next Tab Group"],
        ]),
        App(name: "Textedit", groups: [
            "TextEdit": ["Settings…", "Hide TextEdit", "Hide Others", "Quit TextEdit", "Quit and Keep Windows"],
            "File": ["New", "Open…", "Close", "Close All", "Save", "Save As…", "Duplicate", "Show Properties", "Page Setup…", "Print…"],
            "Edit": ["Undo", "Redo", "Cut", "Copy", "Paste", "Paste and Match Style", "Complete", "Select All", "Attach Files…", "Link…", "Find…", "Find and Replace…", "Find Next", "Find Previous", "Use Selection for Find", "Jump to Selection", "Select Line...", "Show Spelling and Grammar", "Check Document Now", "Start Dictation", "Emoji & Symbols"],
            "Format": ["Show Fonts", "Bold", "Italic", "Underline", "Bigger", "Smaller", "Tighten", "Loosen", "Show Colours", "Copy Style", "Paste Style", "Align Left", "Centre", "Align Right", "Show Ruler", "Copy Ruler", "Paste Ruler", "Make Rich Text", "Wrap to Page"],
            "View": ["Actual Size", "Zoom In", "Zoom Out", "Enter Full Screen"],
            "Window": ["Minimise", "Minimise All", "Fill", "Centre", "Left", "Right", "Top", "Bottom", "Left & Right", "Left & Quarters", "Right & Left", "Right & Quarters", "Top & Bottom", "Top & Quarters", "Bottom & Top", "Bottom & Quarters", "Return to Previous Size"],
            "Help": ["TextEdit Help"],
        ]),
    ]

    /// Builds the `ShortcutGroup` list Keyveil would receive for a captured app,
    /// assigning the same scan-wide ordinal the real service assigns.
    static func groups(for app: App) -> [ShortcutGroup] {
        var ordinal = 0
        return app.groups.map { title, items in
            ShortcutGroup(
                title: title,
                shortcuts: items.map { item in
                    defer { ordinal += 1 }
                    return ShortcutItem(
                        title: item,
                        keys: [],
                        path: "\(title)/\(item)",
                        ordinal: ordinal
                    )
                }
            )
        }
    }

    static func app(named name: String) -> App? {
        all.first { $0.name == name }
    }

}
