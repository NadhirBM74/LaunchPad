import Foundation
import Combine
import Darwin
import IOKit.ps

/// Moniteur léger des statistiques système (CPU, RAM, Batterie)
/// Exécuté avec un intervalle doux pour préserver les ressources de la machine.
@MainActor
final class SystemStatsMonitor: ObservableObject {
    static let shared = SystemStatsMonitor()

    private(set) var cpuPercent: Int = 0
    private(set) var ramPercent: Int = 0
    private(set) var ramUsedGB: Double = 0.0
    private(set) var ramTotalGB: Double = 0.0
    private(set) var batteryPercent: Int = 100
    private(set) var isCharging: Bool = false
    private(set) var hasBattery: Bool = true

    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    nonisolated(unsafe) private var prevUser: UInt32 = 0
    nonisolated(unsafe) private var prevSystem: UInt32 = 0
    nonisolated(unsafe) private var prevIdle: UInt32 = 0
    nonisolated(unsafe) private var prevNice: UInt32 = 0
    private var isMonitoring = false
    private var activeClients = 0
    private var alwaysVisibleClients = 0
    private var isLaunchpadVisible = LaunchpadViewModel.isLaunchpadVisible
    private var hardwareHasBattery: Bool = true
    private var batterySampleCountdown: Int = 0
    private var isWidgetMounted: Bool { activeClients > 0 || alwaysVisibleClients > 0 }
    private var shouldRunTimer: Bool {
        alwaysVisibleClients > 0 || (activeClients > 0 && isLaunchpadVisible)
    }
    private let statsQueue = DispatchQueue(label: "me.LaucnhPad.systemstats", qos: .utility)

    private init() {
        NotificationCenter.default.publisher(for: .launchpadVisibilityDidChange)
            .compactMap { $0.object as? Bool }
            .sink { [weak self] visible in
                guard let self else { return }
                self.isLaunchpadVisible = visible
                if self.shouldRunTimer {
                    self.resumeTimer()
                } else {
                    self.pauseTimer()
                }
            }
            .store(in: &cancellables)
    }

    func startMonitoring(alwaysActive: Bool = false) {
        if alwaysActive {
            alwaysVisibleClients += 1
        } else {
            activeClients += 1
        }
        resumeTimer()
    }

    func stopMonitoring(alwaysActive: Bool = false) {
        if alwaysActive {
            alwaysVisibleClients = max(0, alwaysVisibleClients - 1)
        } else {
            activeClients = max(0, activeClients - 1)
        }
        if !shouldRunTimer {
            pauseTimer()
        }
    }

    private func resumeTimer() {
        guard !isMonitoring, shouldRunTimer else { return }
        isMonitoring = true
        refresh()
        timer = Timer.publish(every: 6.0, tolerance: 1.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.shouldRunTimer else { return }
                self.refresh()
            }
    }

    private func pauseTimer() {
        isMonitoring = false
        timer?.cancel()
        timer = nil
    }

    nonisolated private static let hostPort: mach_port_t = mach_host_self()
    nonisolated private static let pageSize: UInt64 = UInt64(getpagesize())
    nonisolated private static let totalBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    nonisolated private static let totalGBStatic: Double = Double(totalBytes) / 1_073_741_824

    func refresh() {
        let shouldSampleBattery = hardwareHasBattery && batterySampleCountdown <= 0
        if shouldSampleBattery {
            batterySampleCountdown = 9 // ~60 s entre deux sondages IOKit batterie
        } else if batterySampleCountdown > 0 {
            batterySampleCountdown -= 1
        }
        statsQueue.async { [weak self] in
            guard let self else { return }
            let cpu = self.sampleCPU()
            let ram = self.sampleRAM()
            let bat: (hasBattery: Bool, percent: Int, isCharging: Bool)? = shouldSampleBattery ? self.sampleBattery() : nil

            Task { @MainActor [weak self] in
                guard let self else { return }
                var changed = false
                if let cpu, self.cpuPercent != cpu {
                    changed = true
                }
                if let ram {
                    if abs(self.ramUsedGB - ram.usedGB) >= 0.05
                        || abs(self.ramTotalGB - ram.totalGB) >= 0.05
                        || self.ramPercent != ram.percent {
                        changed = true
                    }
                }
                if let bat {
                    if self.hasBattery != bat.hasBattery
                        || (bat.hasBattery && (self.batteryPercent != bat.percent || self.isCharging != bat.isCharging)) {
                        changed = true
                    }
                }
                guard changed else { return }
                // Un seul objectWillChange pour les 7 métriques (au lieu de 7 invalidations SwiftUI en rafale)
                self.objectWillChange.send()
                if let cpu { self.cpuPercent = cpu }
                if let ram {
                    self.ramUsedGB = ram.usedGB
                    self.ramTotalGB = ram.totalGB
                    self.ramPercent = ram.percent
                }
                if let bat {
                    self.hasBattery = bat.hasBattery
                    self.hardwareHasBattery = bat.hasBattery
                    if bat.hasBattery {
                        self.batteryPercent = bat.percent
                        self.isCharging = bat.isCharging
                    }
                }
            }
        }
    }

    // MARK: - CPU

    nonisolated private func sampleCPU() -> Int? {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(Self.hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return nil }
        let u = cpuInfo.cpu_ticks.0
        let s = cpuInfo.cpu_ticks.1
        let i = cpuInfo.cpu_ticks.2
        let n = cpuInfo.cpu_ticks.3

        var computedCPU: Int? = nil
        if prevUser > 0 || prevSystem > 0 || prevIdle > 0 {
            let du = UInt64(u &- prevUser)
            let ds = UInt64(s &- prevSystem)
            let di = UInt64(i &- prevIdle)
            let dn = UInt64(n &- prevNice)
            let total = du + ds + di + dn
            if total > 0 {
                let active = du + ds + dn
                let ratio = Double(active) / Double(total)
                computedCPU = min(100, max(0, Int(round(ratio * 100))))
            }
        }
        prevUser = u
        prevSystem = s
        prevIdle = i
        prevNice = n
        return computedCPU
    }

    // MARK: - RAM

    nonisolated private func sampleRAM() -> (usedGB: Double, totalGB: Double, percent: Int)? {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(Self.hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return nil }
        let pageSize = Self.pageSize
        let active = UInt64(vmStats.active_count) * pageSize
        let wire = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let usedBytes = active + wire + compressed
        let totalBytes = Self.totalBytes

        let usedGB = Double(usedBytes) / 1_073_741_824
        let totalGB = Self.totalGBStatic
        let newRAM = totalBytes > 0 ? min(100, max(0, Int(round((Double(usedBytes) / Double(totalBytes)) * 100)))) : 0
        return (usedGB, totalGB, newRAM)
    }

    // MARK: - Batterie

    nonisolated private func sampleBattery() -> (hasBattery: Bool, percent: Int, isCharging: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return (false, 100, false)
        }
        let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] ?? []
        guard !sources.isEmpty else {
            return (false, 100, false)
        }
        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                let curCap = desc[kIOPSCurrentCapacityKey as String] as? Int ?? -1
                let maxCap = desc[kIOPSMaxCapacityKey as String] as? Int ?? -1
                let isCharging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
                if maxCap > 0 && curCap >= 0 {
                    let pct = min(100, max(0, Int(round((Double(curCap) / Double(maxCap)) * 100))))
                    return (true, pct, isCharging)
                }
            }
        }
        return (false, 100, false)
    }
}
