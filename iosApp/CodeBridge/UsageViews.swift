import SwiftUI
import Charts

struct QuotaView: View {
    let store: BridgeStore
    var body: some View {
        List {
            if store.snapshot?.quotas.isEmpty != false {
                ContentUnavailableView("尚无套餐数据", systemImage: "gauge.with.dots.needle.0percent", description: Text("连接已登录的电脑后刷新。仅支持读取套餐额度的 Agent 会显示。"))
            }
            ForEach(store.snapshot?.quotas ?? []) { quota in
                Section {
                    if quota.status == "ok" {
                        ForEach(Array(quota.limits.enumerated()), id: \.offset) { _, limit in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(limit.label); Spacer(); Text("已用 \(limit.percent)%").monospacedDigit() }
                                ProgressView(value: Double(limit.percent), total: 100).tint(limit.percent >= 80 ? .orange : .accentColor)
                                if let reset = limit.resetsAt {
                                    Text("重置时间：\(Date(timeIntervalSince1970: reset / 1000).formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 6)
                        }
                    } else { Text("暂时无法读取，请检查电脑上的登录状态。").foregroundStyle(.secondary) }
                } header: {
                    HStack { AgentMark(agent: quota.agent); Text("\(agentName(quota.agent))\(quota.planType.map { " · \($0)" } ?? "")") }
                } footer: {
                    if quota.fetchedAt > 0 { Text("更新于 \(Date(timeIntervalSince1970: quota.fetchedAt / 1000).formatted(date: .omitted, time: .shortened))") }
                }
            }
            Button("查看 Token 用量", systemImage: "chart.bar") { store.sheet = .usage }
        }
        .navigationTitle("套餐额度").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("刷新", systemImage: "arrow.clockwise") { store.runtime.refreshQuota() } }
        .task { store.runtime.refreshQuota() }
    }
}

struct UsageView: View {
    let store: BridgeStore
    @State private var days = 1
    @State private var agent = "all"
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("时间范围", selection: $days) { Text("今日").tag(1); Text("7 天").tag(7); Text("30 天").tag(30) }.pickerStyle(.segmented)
                if store.snapshot?.usageFilterable == true {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            agentButton("all")
                            ForEach(store.snapshot?.agents ?? [], id: \.self) { agentButton($0) }
                        }
                    }
                }
                if let usage = store.snapshot?.usage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tokens · \(usage.days.count <= 1 ? "今日" : "\(usage.days.count) 天")").font(.caption).foregroundStyle(.secondary)
                        Text(tokenLabel(usage.total)).font(.system(size: 38, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("\(usage.requestsWindow ?? usage.requestsToday) 次请求").font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.background, in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Label("缓存命中", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                            Spacer()
                            Text((usage.cacheHitPctWindow ?? usage.cacheHitPct).map { "\($0)%" } ?? "暂无数据").monospacedDigit()
                        }.font(.subheadline)
                        Text("\(store.snapshot?.usageAgent.map(agentName) ?? "全部 Agent") · 当前数据显示范围").font(.caption).foregroundStyle(.secondary)
                        if let read = usage.cacheReadTokensWindow, let base = usage.cacheBaseTokensWindow {
                            Text("\(tokenLabel(read)) / \(tokenLabel(base)) Tokens").font(.caption.monospacedDigit())
                            Text("缓存读取 /（输入 + 缓存读取）").font(.caption2).foregroundStyle(.secondary)
                        }
                    }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 18))
                    if let cost = usage.costUsdWindow { LabeledContent("预估花费", value: cost.formatted(.currency(code: "USD"))) }
                    VStack(alignment: .leading) {
                        Text("用量趋势").font(.subheadline.weight(.medium))
                        Chart(Array((usage.days.count == 1 ? usage.hours ?? usage.days : usage.days).enumerated()), id: \.offset) { index, bucket in
                            BarMark(x: .value("周期", index), y: .value("Tokens", bucket.tokens)).cornerRadius(3).foregroundStyle(Color.accentColor)
                        }.frame(height: 150)
                    }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 18))
                    VStack(spacing: 0) {
                        ForEach(Array(usage.models.enumerated()), id: \.offset) { _, model in
                            HStack { AgentMark(agent: model.agent); Text(model.model).lineLimit(1); Spacer(); Text(tokenLabel(model.tokens)).monospacedDigit() }
                                .font(.subheadline).padding(14)
                        }
                    }.background(.background, in: RoundedRectangle(cornerRadius: 18))
                    Text("来自电脑上的本地 Agent 会话记录；与套餐额度分别统计。").font(.caption).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("尚无用量数据", systemImage: "chart.bar", description: Text("连接电脑后可读取本地会话统计。"))
                }
            }.padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Token 用量").navigationBarTitleDisplayMode(.inline)
        .task(id: "\(days)|\(agent)") { store.runtime.fetchUsage(days: Int32(days), agent: agent) }
    }

    private func agentButton(_ id: String) -> some View {
        Button { agent = id } label: {
            HStack(spacing: 5) {
                if id != "all" { AgentMark(agent: id, size: 14) }
                Text(id == "all" ? "全部" : agentName(id))
            }.font(.caption).padding(.horizontal, 11).frame(height: 36)
        }.buttonStyle(.plain).background(agent == id ? Color.accentColor.opacity(0.15) : .clear, in: Capsule())
    }
}
