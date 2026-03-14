//
//  SpeedMonitor.swift
//  SpeedMonitor
//

import Foundation
import Darwin
import Combine

final class SpeedMonitor: ObservableObject {
    @Published private(set) var menuBarText = "0K↓ 0K↑"

    private var timer: Timer?
    private var previousStats: (rx: UInt64, tx: UInt64)?
    private var previousTime = Date()

    // Start periodic polling immediately.
    init() {
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
    }

    // Poll once per second; each tick computes delta against previous snapshot.
    private func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateSpeed()
        }
    }

    // Convert byte counters to throughput (bytes/sec) and publish compact UI text.
    private func updateSpeed() {
        let stats = getAggregatedNetworkStats()
        let currentTime = Date()
        let timeDiff = currentTime.timeIntervalSince(previousTime)

        if let previousStats, timeDiff > 0 {
            let rxDelta = stats.rx >= previousStats.rx ? stats.rx - previousStats.rx : 0
            let txDelta = stats.tx >= previousStats.tx ? stats.tx - previousStats.tx : 0
            let downSpeed = Double(rxDelta) / timeDiff
            let upSpeed = Double(txDelta) / timeDiff
            menuBarText = "\(formatCompact(downSpeed))↓ \(formatCompact(upSpeed))↑"
        }

        self.previousStats = stats
        self.previousTime = currentTime
    }

    // Compact metric formatting for menu-bar footprint.
    private func formatCompact(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1024 * 1024 * 1024 {
            return String(format: "%.1fG", bytesPerSec / (1024 * 1024 * 1024))
        }
        if bytesPerSec >= 1024 * 1024 {
            return String(format: "%.1fM", bytesPerSec / (1024 * 1024))
        }
        return String(format: "%.0fK", bytesPerSec / 1024)
    }

    // Sum RX/TX over all active non-loopback interfaces.
    private func getAggregatedNetworkStats() -> (rx: UInt64, tx: UInt64) {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return (0, 0) }
        defer { freeifaddrs(addresses) }

        var totalRx: UInt64 = 0
        var totalTx: UInt64 = 0
        var pointer = addresses

        while pointer != nil {
            defer { pointer = pointer?.pointee.ifa_next }
            guard let current = pointer?.pointee else { continue }

            guard let addr = current.ifa_addr else { continue }
            guard Int32(addr.pointee.sa_family) == AF_LINK else { continue }

            let flags = Int32(current.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if !isUp || !isRunning || isLoopback { continue }

            guard let data = current.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            totalRx += UInt64(data.pointee.ifi_ibytes)
            totalTx += UInt64(data.pointee.ifi_obytes)
        }

        return (totalRx, totalTx)
    }
}
