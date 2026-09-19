//
//  TrollBatteryWidgetBundle.swift
//  TrollBatteryWidget
//
//  Widget Extension 入口。目前只承载一个 Live Activity。
//

import WidgetKit
import SwiftUI

@main
struct TrollBatteryWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrollBatteryLiveActivityWidget()
    }
}
