import WidgetKit
import SwiftUI

@main
struct DorisWidgetBundle: WidgetBundle {
    var body: some Widget {
        TasksWidget()
        EventsWidget()
    }
}
