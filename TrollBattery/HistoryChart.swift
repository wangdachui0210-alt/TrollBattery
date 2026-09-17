//
//  HistoryChart.swift
//  TrollBattery
//
//  纯 SwiftUI Path 绘制的功率曲线，兼容 iOS 14（不依赖 Swift Charts）。
//

import SwiftUI

struct PowerHistoryChart: View {

    let samples: [PowerSample]
    var accent: Color = Color(red: 0.20, green: 0.60, blue: 1.00)

    @Environment(\.colorScheme) private var colorScheme

    private var gridColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var labelColor: Color {
        Color(UIColor.tertiaryLabel)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                grid(in: geo.size)

                if samples.count > 1 {
                    let points = normalized(in: geo.size)

                    fillPath(points, in: geo.size)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [accent.opacity(0.32), accent.opacity(0.02)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    linePath(points)
                        .stroke(
                            accent,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )

                    if let last = points.last {
                        Circle()
                            .fill(accent)
                            .frame(width: 7, height: 7)
                            .position(last)
                    }
                } else {
                    Text("正在采样…")
                        .font(.system(size: 12))
                        .foregroundColor(labelColor)
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                if let peak = samples.map({ $0.watts }).max(), peak > 0 {
                    Text(String(format: "峰值 %.2f W", peak))
                        .font(.system(size: 10))
                        .foregroundColor(labelColor)
                        .padding(.leading, 2)
                }
            }
        }
    }

    // MARK: - 绘制

    private func grid(in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<4) { index in
                let y = size.height * CGFloat(index) / 3.0
                Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(gridColor, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
    }

    private func normalized(in size: CGSize) -> [CGPoint] {
        guard !samples.isEmpty else { return [] }
        let peak = max(samples.map { $0.watts }.max() ?? 1, 0.01)
        let count = samples.count
        let usableHeight = size.height - 6

        return samples.enumerated().map { index, sample in
            let x = count == 1
                ? size.width / 2
                : size.width * CGFloat(index) / CGFloat(count - 1)
            let ratio = CGFloat(min(sample.watts / peak, 1.0))
            let y = size.height - 3 - usableHeight * ratio
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func fillPath(_ points: [CGPoint], in size: CGSize) -> Path {
        var path = linePath(points)
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: first.x, y: size.height))
        path.closeSubpath()
        return path
    }
}
