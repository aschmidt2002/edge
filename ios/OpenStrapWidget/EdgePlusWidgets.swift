//
//  EdgePlusWidgets.swift
//  OpenStrapWidget
//
//  Edge+: four more widgets on the same App Group snapshot — the iOS siblings
//  of ActivityWidgetProvider, StressWidgetProvider, CoachWidgetProvider and
//  QuickActionsWidgetProvider on Android.
//
//   · Activity — steps against the goal Home's steps card uses, active
//     energy and movement minutes.
//   · Stress — the day's score, its band in words, and the calm / balanced /
//     stressed split as one bar.
//   · Coach — the Recovery dial and what the coach suggests for today.
//   · Quick actions — breathing, water, alarm, workouts in one tap.
//
//  Same rules as StrapWidgetKit.swift: every number and every word arrives
//  resolved from `WidgetService.push`; -1 means "nothing measured" and is
//  rendered as a word, never a 0; a stale snapshot shows the no-data face.
//
//  Taps deep-link through `openstrap://route/<path>`. SceneDelegate copies the
//  path into the App Group's `pending_route` — the same latch the Siri intents
//  use — and AppState.checkPendingSiriRoute routes it on launch/resume.
//

import WidgetKit
import SwiftUI

// MARK: - Snapshot extras

/// The keys these four read on top of `SW.Snapshot`.
struct EdgeExtras {
  let steps, stepGoal, kcal, activeMin: Int
  let stressScore, stressTier, calmMin, balancedMin, stressedMin: Int
  let stressBand, coachLine, coachDetail: String

  static func read() -> EdgeExtras {
    let d = UserDefaults(suiteName: SW.appGroup)
    func i(_ k: String) -> Int { d?.object(forKey: k) as? Int ?? -1 }
    func s(_ k: String) -> String { d?.string(forKey: k) ?? "" }
    return EdgeExtras(
      steps: i("steps"), stepGoal: i("step_goal"), kcal: i("active_kcal"),
      activeMin: i("active_min"),
      stressScore: i("stress_score"), stressTier: i("stress_tier"),
      calmMin: i("stress_calm_min"), balancedMin: i("stress_balanced_min"),
      stressedMin: i("stress_stressed_min"),
      stressBand: s("stress_band"), coachLine: s("coach_line"),
      coachDetail: s("coach_detail"))
  }

  static let placeholder = EdgeExtras(
    steps: 8412, stepGoal: 10000, kcal: 420, activeMin: 46,
    stressScore: 34, stressTier: 1, calmMin: 190, balancedMin: 260, stressedMin: 40,
    stressBand: "Balanced", coachLine: "Zone 2 run, 40 minutes",
    coachDetail: "Recovery is good — build aerobic base without digging a hole.")

  /// The steps as a ring, so it draws through the same `SW.Dial` as Home's.
  var stepsRing: SW.RingData {
    guard steps >= 0 else {
      return SW.RingData(state: 2, value: "No steps", sub: "",
                         why: "Nothing counted yet today.", frac: -1)
    }
    return SW.RingData(
      state: 0, value: steps.formatted(),
      sub: stepGoal > 0 ? "of \(stepGoal.formatted())" : "steps",
      why: "", frac: stepGoal > 0 ? Double(steps) / Double(stepGoal) : -1)
  }

  var stressRing: SW.RingData {
    guard stressScore >= 0 else {
      return SW.RingData(state: 2, value: "No score", sub: "",
                         why: "Wear the band to see today's.", frac: -1)
    }
    return SW.RingData(state: 0, value: "\(stressScore)", sub: stressBand,
                       why: "", frac: Double(stressScore) / 100)
  }

  /// "420 kcal · 46 min active" — each half only when there is one.
  var activityFoot: String {
    [kcal >= 0 ? "\(kcal) kcal" : nil, activeMin >= 0 ? "\(activeMin) min active" : nil]
      .compactMap { $0 }.joined(separator: " · ")
  }

  /// Band index → colour. The cut-offs live in Dart (StressData.tier).
  func stressColor(_ p: SW.Pal) -> Color {
    switch stressTier {
    case 0: return p.good
    case 1: return p.sleep
    case 2: return p.warn
    case 3: return p.bad
    default: return p.ink3
    }
  }
}

struct EdgeEntry: TimelineEntry {
  var date: Date
  let snap: SW.Snapshot
  let x: EdgeExtras

  var fresh: Bool { SW.fresh(snap, at: date) }

  static let placeholder = EdgeEntry(date: Date(), snap: .placeholder, x: .placeholder)
}

struct EdgeProvider: TimelineProvider {
  func placeholder(in context: Context) -> EdgeEntry { .placeholder }

  func getSnapshot(in context: Context, completion: @escaping (EdgeEntry) -> Void) {
    completion(context.isPreview
               ? .placeholder
               : EdgeEntry(date: Date(), snap: SW.read(), x: .read()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<EdgeEntry>) -> Void) {
    let snap = SW.read()
    let x = EdgeExtras.read()
    completion(SW.timeline(snap, Date()) { EdgeEntry(date: $0, snap: snap, x: x) })
  }
}

enum EdgeRoute {
  /// `openstrap://route/<path>` — see SceneDelegate.latchWidgetRoute.
  static func url(_ path: String) -> URL {
    URL(string: "openstrap://route\(path)") ?? URL(string: "openstrap://route/today")!
  }
}

// MARK: - Shared bits

/// A rounded bar of (fraction, colour) segments over the track.
private struct SplitBar: View {
  let parts: [(Double, Color)]
  var height: CGFloat = 6

  var body: some View {
    let p = SW.pal
    GeometryReader { geo in
      HStack(spacing: 0) {
        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
          Rectangle().fill(part.1)
            .frame(width: geo.size.width * max(0, min(part.0, 1)))
        }
        Spacer(minLength: 0)
      }
      .background(p.track)
      .clipShape(Capsule())
    }
    .frame(height: height)
  }
}

// MARK: - Activity

private struct ActivityView: View {
  @Environment(\.widgetFamily) var family
  let x: EdgeExtras

  var body: some View {
    let p = SW.pal
    let r = x.stepsRing
    switch family {
    case .accessoryCircular:
      if r.measured, r.frac >= 0 {
        Gauge(value: min(r.frac, 1)) {
          Image(systemName: "figure.walk")
        } currentValueLabel: {
          Text(x.steps >= 10000 ? "\(x.steps / 1000)k" : "\(x.steps)")
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
      } else {
        Image(systemName: "figure.walk").font(.system(size: 18)).widgetAccentable()
      }
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 2) {
        Text(r.measured ? "Steps \(r.value)" : "No steps yet")
          .font(.system(size: 13, weight: .bold)).widgetAccentable()
        if r.measured, !r.sub.isEmpty { Text(r.sub).font(.system(size: 12)) }
        if !x.activityFoot.isEmpty {
          Text(x.activityFoot).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
        }
      }
    case .accessoryInline:
      Label(r.measured ? "\(r.value) steps" : "No steps yet", systemImage: "figure.walk")
    default:
      VStack(spacing: 6) {
        SW.Dial(r: r, symbol: "figure.walk", accent: p.good, size: 60, line: 8)
        SW.RingText(label: "Steps", r: r, accent: p.good, valueSize: 22)
        if !x.activityFoot.isEmpty {
          Text(x.activityFoot).font(.system(size: 11)).foregroundStyle(p.ink3)
            .lineLimit(1).minimumScaleFactor(0.8)
        }
      }
      .padding(12)
    }
  }
}

struct OpenStrapActivityWidget: Widget {
  let kind = "OpenStrapActivityWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: EdgeProvider()) { entry in
      EdgeEntryView(entry: entry, route: "/today/steps") { ActivityView(x: entry.x) }
    }
    .configurationDisplayName("Activity")
    .description("Today's steps against your goal, active energy and movement minutes.")
    .supportedFamilies([.systemSmall, .accessoryCircular,
                        .accessoryRectangular, .accessoryInline])
  }
}

// MARK: - Stress

private struct StressView: View {
  @Environment(\.widgetFamily) var family
  let x: EdgeExtras

  private var split: [(Double, Color)]? {
    let p = SW.pal
    let parts = [x.calmMin, x.balancedMin, x.stressedMin].map { max($0, 0) }
    let total = parts.reduce(0, +)
    guard x.stressScore >= 0, total > 0 else { return nil }
    return zip(parts, [p.good, p.sleep, p.warn]).map { (Double($0) / Double(total), $1) }
  }

  var body: some View {
    let p = SW.pal
    let r = x.stressRing
    switch family {
    case .accessoryCircular:
      if r.measured {
        Gauge(value: min(r.frac, 1)) {
          Image(systemName: "gauge.with.dots.needle.33percent")
        } currentValueLabel: {
          Text(r.value)
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
      } else {
        Image(systemName: "gauge.with.dots.needle.33percent")
          .font(.system(size: 18)).widgetAccentable()
      }
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 2) {
        Text(r.measured ? "Stress \(r.value)" : "No stress score")
          .font(.system(size: 13, weight: .bold)).widgetAccentable()
        Text(r.measured ? r.sub : r.why).font(.system(size: 12))
        if r.measured {
          Text("Calm \(hm(x.calmMin)) · Stressed \(hm(x.stressedMin))")
            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
        }
      }
    default:
      VStack(spacing: 5) {
        SW.Dial(r: r, symbol: "gauge.with.dots.needle.33percent",
                accent: x.stressColor(p), size: 54, line: 7)
        SW.RingText(label: "Stress", r: r, accent: x.stressColor(p), valueSize: 22)
        if let split {
          SplitBar(parts: split).padding(.horizontal, 6)
          Text("Calm \(hm(x.calmMin)) · Stressed \(hm(x.stressedMin))")
            .font(.system(size: 10)).foregroundStyle(p.ink3)
            .lineLimit(1).minimumScaleFactor(0.8)
        }
      }
      .padding(12)
    }
  }

  /// The phone's own `hm()`: "45m" / "3h 10m".
  private func hm(_ m: Int) -> String {
    let v = max(m, 0)
    return v < 60 ? "\(v)m" : String(format: "%dh %02dm", v / 60, v % 60)
  }
}

struct OpenStrapStressWidget: Widget {
  let kind = "OpenStrapStressWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: EdgeProvider()) { entry in
      EdgeEntryView(entry: entry, route: "/heart") { StressView(x: entry.x) }
    }
    .configurationDisplayName("Stress")
    .description("Today's stress score and how your day split between calm and stressed.")
    .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
  }
}

// MARK: - Coach

private struct CoachView: View {
  @Environment(\.widgetFamily) var family
  let snap: SW.Snapshot
  let x: EdgeExtras

  private var title: String { x.coachLine.isEmpty ? "No plan yet" : x.coachLine }
  private var detail: String {
    x.coachLine.isEmpty ? "Open OpenStrap for today's coaching." : x.coachDetail
  }
  private var cap: String {
    let r = snap.recovery
    return r.measured && !r.sub.isEmpty ? "TODAY · \(r.value) \(r.sub.uppercased())" : "TODAY"
  }

  var body: some View {
    let p = SW.pal
    switch family {
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 2) {
        Text(cap).font(.system(size: 11, weight: .semibold)).widgetAccentable()
        Text(title).font(.system(size: 13, weight: .bold)).lineLimit(2)
      }
    case .accessoryInline:
      Label(title, systemImage: "sparkles")
    default:
      HStack(alignment: .center, spacing: 12) {
        SW.Dial(r: snap.recovery, symbol: "sparkles",
                accent: SW.tierColor(snap.tier, p), size: 52, line: 6)
        VStack(alignment: .leading, spacing: 3) {
          Text(cap).font(SW.over).tracking(0.5).foregroundStyle(p.ink3).lineLimit(1)
          Text(title).font(.system(size: 15, weight: .semibold))
            .foregroundStyle(x.coachLine.isEmpty ? p.ink2 : p.ink).lineLimit(2)
          if !detail.isEmpty {
            Text(detail).font(.system(size: 12)).foregroundStyle(p.ink3).lineLimit(3)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(14)
    }
  }
}

struct OpenStrapCoachWidget: Widget {
  let kind = "OpenStrapCoachWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: EdgeProvider()) { entry in
      EdgeEntryView(entry: entry, route: "/today") { CoachView(snap: entry.snap, x: entry.x) }
    }
    .configurationDisplayName("Coach tip")
    .description("Your recovery and what the coach suggests for today.")
    .supportedFamilies([.systemMedium, .accessoryRectangular, .accessoryInline])
  }
}

// MARK: - Shared entry view

/// Freshness gate, card background and tap route — once, for the three
/// snapshot widgets above.
private struct EdgeEntryView<Content: View>: View {
  @Environment(\.widgetFamily) var family
  let entry: EdgeEntry
  let route: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    Group {
      if entry.fresh { content() } else { SW.NoData() }
    }
    .widgetURL(EdgeRoute.url(route))
    .strapBackground(family)
  }
}

// MARK: - Quick actions

private struct QuickAction: Identifiable {
  let id: String
  let label: String
  let symbol: String
  let route: String
  let color: (SW.Pal) -> Color
}

private let quickActions: [QuickAction] = [
  QuickAction(id: "breath", label: "Breathe", symbol: "wind", route: "/breathing") { $0.good },
  QuickAction(id: "water", label: "Water", symbol: "drop.fill", route: "/water") { $0.sleep },
  QuickAction(id: "alarm", label: "Alarm", symbol: "alarm", route: "/alarm") { $0.warn },
  QuickAction(id: "workout", label: "Workout", symbol: "dumbbell.fill", route: "/workouts") { $0.move },
]

struct QuickEntry: TimelineEntry {
  let date: Date
}

struct QuickProvider: TimelineProvider {
  func placeholder(in context: Context) -> QuickEntry { QuickEntry(date: Date()) }
  func getSnapshot(in context: Context, completion: @escaping (QuickEntry) -> Void) {
    completion(QuickEntry(date: Date()))
  }
  /// Nothing to age — `.never`; the app reloads it when the theme flips.
  func getTimeline(in context: Context, completion: @escaping (Timeline<QuickEntry>) -> Void) {
    completion(Timeline(entries: [QuickEntry(date: Date())], policy: .never))
  }
}

private struct QuickView: View {
  @Environment(\.widgetFamily) var family

  var body: some View {
    let p = SW.pal
    HStack(spacing: 0) {
      ForEach(quickActions) { a in
        Link(destination: EdgeRoute.url(a.route)) {
          VStack(spacing: 6) {
            ZStack {
              Circle().fill(a.color(p).opacity(0.18))
              Image(systemName: a.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(a.color(p))
            }
            .frame(width: 48, height: 48)
            Text(a.label).font(.system(size: 12, weight: .medium))
              .foregroundStyle(p.ink2).lineLimit(1)
          }
          .frame(maxWidth: .infinity)
        }
      }
    }
    .padding(.horizontal, 8)
    .strapBackground(family)
  }
}

struct OpenStrapQuickWidget: Widget {
  let kind = "OpenStrapQuickWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QuickProvider()) { _ in
      QuickView()
    }
    .configurationDisplayName("Quick actions")
    .description("Start breathing, log water, set the alarm or open workouts in one tap.")
    .supportedFamilies([.systemMedium])
  }
}
