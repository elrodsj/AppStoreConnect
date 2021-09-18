//
//  Widgets.swift
//  AC Widget by NO-COMMENT
//

import WidgetKit
import SwiftUI
import Intents
import Promises

struct Provider: IntentTimelineProvider {
    func placeholder(in context: Context) -> ACStatEntry {
        ACStatEntry(date: Date(), data: .example, filteredApps: [], color: .accentColor, configuration: WidgetConfigurationIntent())
    }

    func getSnapshot(for configuration: WidgetConfigurationIntent, in context: Context, completion: @escaping (ACStatEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
        } else {
            getApiData(currencyParam: configuration.currency, apiKeyParam: configuration.apiKey)
                .then { data in
                    let isNewData = data.getRawData(.proceeds, lastNDays: 3).contains { (proceed) -> Bool in
                        Calendar.current.isDateInToday(proceed.1) ||
                        Calendar.current.isDateInYesterday(proceed.1)
                    }

                    let entry = ACStatEntry(
                        date: Date(),
                        data: data,
                        filteredApps: configuration.filteredApps?.compactMap({ $0.toACApp(data: data) }) ?? [],
                        color: configuration.apiKey?.getColor() ?? .accentColor,
                        configuration: configuration,
                        relevance: isNewData ? .high : .medium
                    )
                    completion(entry)
                }
                .catch { err in
                    let entry = ACStatEntry(date: Date(), data: nil, filteredApps: [], error: err as? APIError, color: configuration.apiKey?.getColor() ?? .accentColor, configuration: configuration, relevance: .low)
                    completion(entry)
                }
        }
    }

    func getTimeline(for configuration: WidgetConfigurationIntent, in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        var entries: [ACStatEntry] = []

        getApiData(currencyParam: configuration.currency, apiKeyParam: configuration.apiKey)
            .then { data in
                let isNewData = data.getRawData(.proceeds, lastNDays: 3).contains { (proceed) -> Bool in
                    Calendar.current.isDateInToday(proceed.1) ||
                    Calendar.current.isDateInYesterday(proceed.1)
                }

                let entry = ACStatEntry(date: Date(),
                                        data: data,
                                        filteredApps: configuration.filteredApps?.compactMap({ $0.toACApp(data: data) }) ?? [],
                                        color: configuration.apiKey?.getColor() ?? .accentColor,
                                        configuration: configuration,
                                        relevance: isNewData ? .high : .medium)
                entries.append(entry)

                // Report is not available yet. Daily reports for the Americas are available by 5 am Pacific Time; Japan, Australia, and New Zealand by 5 am Japan Standard Time; and 5 am Central European Time for all other territories.

                var nextUpdate = Date()

                if nextUpdate.getCETHour() <= 12 {
                    // every 15 minutes
                    nextUpdate = nextUpdate.advanced(by: 15 * 60)
                } else {
                    nextUpdate = nextUpdate.nextFullHour()
                }

                let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
                completion(timeline)
            }
            .catch { err in
                let entry = ACStatEntry(date: Date(), data: nil, filteredApps: [], error: err as? APIError, color: .accentColor, configuration: configuration)
                entries.append(entry)

                var nextUpdateDate = Date()
                if err as? APIError == .invalidCredentials {
                    nextUpdateDate = nextUpdateDate.advanced(by: 24 * 60)
                } else {
                    // wenn api down, update in 5 min erneut
                    nextUpdateDate = nextUpdateDate.advanced(by: 5 * 60)
                }

                let timeline = Timeline(entries: entries, policy: .after(nextUpdateDate))
                completion(timeline)
            }
    }

    func getApiData(currencyParam: CurrencyParam?, apiKeyParam: ApiKeyParam?) -> Promise<ACData> {
        guard let apiKey = apiKeyParam?.toApiKey(),
              APIKey.getApiKey(apiKeyId: apiKey.id) != nil else {
                  let promise = Promise<ACData>.pending()
                  promise.reject(APIError.invalidCredentials)
                  return promise
              }
        let api = AppStoreConnectApi(apiKey: apiKey)
        return api.getData(currency: currencyParam)
    }
}

struct ACStatEntry: TimelineEntry {
    let date: Date
    let data: ACData?
    let filteredApps: [ACApp]
    var error: APIError?
    let color: Color
    let configuration: WidgetConfigurationIntent
    var relevance: TimelineEntryRelevance?
}

extension ACStatEntry {
    static let placeholder = ACStatEntry(date: Date(), data: .example, filteredApps: [], color: .accentColor, configuration: WidgetConfigurationIntent())
}

extension TimelineEntryRelevance {
    static let low = TimelineEntryRelevance(score: 0, duration: 0)
    static let medium = TimelineEntryRelevance(score: 50, duration: 60 * 60)
    static let high = TimelineEntryRelevance(score: 100, duration: 60 * 60)
}

struct WidgetsEntryView: View {
    @Environment(\.widgetFamily) var size

    var entry: Provider.Entry

    var body: some View {
        if let data = entry.data {
            switch size {
            case .systemSmall:
                SummarySmall(data: data, color: entry.color, filteredApps: entry.filteredApps)
            case .systemMedium:
                SummaryMedium(data: data, color: entry.color, filteredApps: entry.filteredApps)
            case .systemLarge:
                SummaryLarge(data: data, color: entry.color, filteredApps: entry.filteredApps)
            case .systemExtraLarge:
                SummaryExtraLarge(data: data, color: entry.color, filteredApps: entry.filteredApps)
            default:
                ErrorWidget(error: .unknown)
            }
        } else {
            ErrorWidget(error: entry.error ?? .unknown)
        }
    }
}

@main
struct Widgets: Widget {
    let kind: String = "Widgets"

    var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: WidgetConfigurationIntent.self, provider: Provider()) { entry in
            WidgetsEntryView(entry: entry)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.widgetBackground)
        }
        .configurationDisplayName("WIDGET_NAME")
        .description("WIDGET_DESC")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct Widgets_Previews: PreviewProvider {
    static var previews: some View {
        WidgetsEntryView(entry: ACStatEntry(date: Date(), data: .example, filteredApps: [.mockApp], color: .accentColor, configuration: WidgetConfigurationIntent()))
            .previewContext(WidgetPreviewContext(family: .systemSmall))

        WidgetsEntryView(entry: ACStatEntry(date: Date(), data: .example, filteredApps: [.mockApp], color: .accentColor, configuration: WidgetConfigurationIntent()))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}
