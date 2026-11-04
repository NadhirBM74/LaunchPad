import Foundation
import Combine
import Darwin
import IOKit.ps

/// Moniteur léger des statistiques système (CPU, RAM, Batterie)
/// Exécuté avec un intervalle doux pour préserver les ressources de la machine.
@MainActor
final class SystemStatsMonitor: ObservableObject {
    static let shared = SystemStatsMonitor()

    @Published private(set) var cpuPercent: Int = 0
    @Published private(set) var ramPercent: Int = 0
    @Published private(set) var ramUsedGB: Double = 0.0
    @Published private(set) var ramTotalGB: Double = 0.0
    @Published private(set) var batteryPercent: Int = 100
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var hasBattery: Bool = true

    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    nonisolated(unsafe) private var prevUser: UInt32 = 0
    nonisolated(unsafe) private var prevSystem: UInt32 = 0
    nonisolated(unsafe) private var prevIdle: UInt32 = 0
    nonisolated(unsafe) private var prevNice: UInt32 = 0
    private var isMonitoring = false
    private var isWidgetMounted = false
    private let statsQueue = DispatchQueue(label: "me.LaucnhPad.systemstats", qos: .utility)

    private init() {
        NotificationCenter.default.publisher(for: .launchpadVisibilityDidChange)
            .compactMap { $0.object as? Bool }
            .sink { [weak self] isVisible in
                guard let self else { return }
                if isVisible && self.isWidgetMounted {
                    self.resumeTimer()
                } else if !isVisible {
                    self.pauseTimer()
                }
            }
            .store(in: &cancellables)
    }

    func startMonitoring() {
        isWidgetMounted = true
        resumeTimer()
    }

    func stopMonitoring() {
        isWidgetMounted = false
        pauseTimer()
    }

    private func resumeTimer() {
        guard !isMonitoring, LaunchpadViewModel.isLaunchpadVisible else { return }
        isMonitoring = true
        refresh()
        timer = Timer.publish(every: 6.0, tolerance: 1.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, LaunchpadViewModel.isLaunchpadVisible, self.isWidgetMounted else { return }
                self.refresh()
            }
    }

    private func pauseTimer() {
        isMonitoring = false
        timer?.cancel()
        timer = nil
    }

    func refresh() {
        statsQueue.async { [weak self] in
            guard let self else { return }
            let cpu = self.sampleCPU()
            let ram = self.sampleRAM()
            let bat = self.sampleBattery()

            Task { @MainActor [weak self] in
                guard let self else { return }
                if let cpu, self.cpuPercent != cpu {
                    self.cpuPercent = cpu
                }
                if let ram {
                    if abs(self.ramUsedGB - ram.usedGB) >= 0.05 {
                        self.ramUsedGB = ram.usedGB
                    }
                    if abs(self.ramTotalGB - ram.totalGB) >= 0.05 {
                        self.ramTotalGB = ram.totalGB
                    }
                    if self.ramPercent != ram.percent {
                        self.ramPercent = ram.percent
                    }
                }
                if self.hasBattery != bat.hasBattery {
                    self.hasBattery = bat.hasBattery
                }
                if bat.hasBattery {
                    if self.batteryPercent != bat.percent {
                        self.batteryPercent = bat.percent
                    }
                    if self.isCharging != bat.isCharging {
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
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return nil }
        let u = cpuInfo.cpu_ticks.0
        let s = cpuInfo.cpu_ticks.1
        let i = cpuInfo.cpu_ticks.2
        let n = cpuInfo.cpu_ticks.3

        var computedCPU: Int? = nil
        if prevUser > 0 || prevSystem > 0 || prevIdle > 0 {
            let du = u >= prevUser ? u - prevUser : 0
            let ds = s >= prevSystem ? s - prevSystem : 0
            let di = i >= prevIdle ? i - prevIdle : 0
            let dn = n >= prevNice ? n - prevNice : 0
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
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(getpagesize())
        let active = UInt64(vmStats.active_count) * pageSize
        let wire = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let usedBytes = active + wire + compressed
        let totalBytes = ProcessInfo.processInfo.physicalMemory

        let usedGB = Double(usedBytes) / 1_073_741_824
        let totalGB = Double(totalBytes) / 1_073_741_824
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
