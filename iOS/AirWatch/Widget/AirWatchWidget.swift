import ActivityKit
import SwiftUI
import WidgetKit

@main
struct AirWatchWidgets: WidgetBundle {
    var body: some Widget {
        AirWatchLiveActivity()
    }
}

struct AirWatchLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AirWatchAttributes.self) { context in
            VStack(alignment: .leading) {
                Text(context.state.headline).bold()
                Text(context.state.detail).lineLimit(2)
            }.padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack {
                        Text(context.state.headline).bold()
                        Text(context.state.detail).lineLimit(2)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.fault ? "exclamationmark.triangle.fill" : "airplane")
            } compactTrailing: {
                Text(context.state.fault ? "FAULT" : "FACTOR")
            } minimal: {
                Image(systemName: context.state.fault ? "exclamationmark.triangle.fill" : "airplane")
            }
        }
    }
}
