//  MeatNetLinkRSSITracker.swift
//  Smooths the RSSI MeatNet Nodes report for their peers in heartbeats.

/*--
MIT License

Copyright (c) 2026 Combustion Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--*/

import Foundation

/// Keeps an EWMA of the RSSI each MeatNet Node reports for each of its peers, matching how
/// `Device.rssiEWMA` smooths the RSSI of advertisements this phone receives directly.
///
/// Heartbeats can reach the phone through any connected Node, so averages are keyed by the
/// reporting Node and peer rather than stored on the `MeatNetNode` that forwarded them.
final class MeatNetLinkRSSITracker {
    /// Same span as `Device.rssiEWMA`.
    static let span: UInt32 = 6

    /// A link that hasn't been reported for this long restarts from its next reading. Matches
    /// `Device`'s stale timeout.
    static let staleTimeout: TimeInterval = 15.0

    private struct LinkKey: Hashable {
        let reporter: String
        let peer: String
    }

    private struct HeartbeatKey: Hashable {
        let reporter: String
        let inbound: Bool
    }

    private struct LinkAverage {
        let ewma = EWMA(span: MeatNetLinkRSSITracker.span)
        var lastUpdated: Date
    }

    private let lock = NSLock()
    private var averages: [LinkKey: LinkAverage] = [:]
    private var lastRequestIds: [HeartbeatKey: UInt32] = [:]

    /// Adds every present peer's RSSI from the heartbeat to its link average.
    func record(_ heartbeat: NodeHeartbeatRequest, receivedAt date: Date = Date()) {
        let reporter = Self.canonicalSerial(heartbeat.serialNumber)
        guard !reporter.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        // The same heartbeat can arrive once through each connected Node. Count it once.
        let heartbeatKey = HeartbeatKey(reporter: reporter, inbound: heartbeat.inbound)
        guard lastRequestIds[heartbeatKey] != heartbeat.requestId else { return }
        lastRequestIds[heartbeatKey] = heartbeat.requestId

        for detail in heartbeat.connectionDetails {
            let peer = Self.canonicalSerial(detail.serialNumber)
            // Non-negative RSSI means the Node had no reading for this peer.
            guard detail.present, !peer.isEmpty, detail.rssi < 0 else { continue }

            let key = LinkKey(reporter: reporter, peer: peer)
            var average = averages[key] ?? LinkAverage(lastUpdated: date)
            if date.timeIntervalSince(average.lastUpdated) > Self.staleTimeout {
                average.ewma.reset()
            }
            average.ewma.put(value: Float(detail.rssi))
            average.lastUpdated = date
            averages[key] = average
        }
    }

    /// Smoothed RSSI (dBm) for the link between the heartbeat's Node and the peer, or `nil` if
    /// the link has no recent reading.
    func smoothedRSSI(for detail: NodeHeartbeatRequest.ConnectionDetail,
                      reportedBy heartbeat: NodeHeartbeatRequest,
                      at date: Date = Date()) -> Float? {
        let key = LinkKey(reporter: Self.canonicalSerial(heartbeat.serialNumber),
                          peer: Self.canonicalSerial(detail.serialNumber))

        lock.lock()
        defer { lock.unlock() }

        guard let average = averages[key],
              date.timeIntervalSince(average.lastUpdated) <= Self.staleTimeout else {
            return nil
        }
        return average.ewma.get()
    }

    private static func canonicalSerial(_ serialNumber: String) -> String {
        serialNumber
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            .uppercased()
    }
}
