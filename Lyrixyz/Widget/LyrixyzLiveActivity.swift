import WidgetKit
import SwiftUI
import ActivityKit

@main
struct LyrixyzWidgetBundle: WidgetBundle {
    var body: some Widget {
        LyrixyzLiveActivity()
    }
}

struct LyrixyzLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsAttributes.self) { context in
            // Lock Screen banner
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.caption.bold())
                        .foregroundStyle(.pink)
                    Text("\(context.state.track) — \(context.state.artist)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(context.state.line)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .lineLimit(2)
                if !context.state.nextLine.isEmpty {
                    Text(context.state.nextLine)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .activityBackgroundTint(Color.black.opacity(0.8))
            .activitySystemActionForegroundColor(.pink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "music.note")
                        .font(.title3.bold())
                        .foregroundStyle(.pink)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.state.line)
                            .font(.system(.headline, design: .rounded).weight(.heavy))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        if !context.state.nextLine.isEmpty {
                            Text(context.state.nextLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.state.track) — \(context.state.artist)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "music.note")
                    .foregroundStyle(.pink)
            } compactTrailing: {
                Text(context.state.line)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 72)
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundStyle(.pink)
            }
        }
    }
}
