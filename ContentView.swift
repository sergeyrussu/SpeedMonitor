//
//  ContentView.swift
//  SpeedMonitor
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var speedMonitor: SpeedMonitor

    var body: some View {
        // Minimal fallback view; primary UI is rendered in the menu bar.
        Text(speedMonitor.menuBarText)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }
}
