import AppKit
import Darwin
import Foundation
import QuartzCore

/// Banc de mesure de performances réel (uniquement activé par l'argument CLI `--perf-benchmark`).
/// Aucun coût CPU/RAM en utilisation normale.
@MainActor
final class PerformanceBenchmark {
    struct MemorySnapshot: Codable {
        let physFootprintMB: Double
        let rssMB: Double
    }

    struct FrameMetrics: Codable {
        let durationSeconds: Double
        let displayMaxHz: Int
        let displayFrames: Int
        let displayFPS: Double
        let droppedFrames: Int
        let workSamples: Int
        let workP50Ms: Double
        let workP95Ms: Double
        let workMaxMs: Double
        let within8_33msPct: Double
        let within16_67msPct: Double
        let cpuPct: Double
    }

    struct Report: Codable {
        let version: String
        let displayMaxHz: Int
        let didFinishLaunchingMs: Double
        let startupCPU_ms: Double
        let startupRAM: MemorySnapshot
        let firstShowMs: Double
        let warmReopenMs: Double
        let visibleRAM: MemorySnapshot
        let swipe120Hz: FrameMetrics
        let jiggleEditMode: FrameMetrics
        let widgetGalleryOpenMs: Double
        let widgetGalleryMetrics: FrameMetrics
        let peakRAM: MemorySnapshot
        let settingsFirstOpenMs: Double
        let settingsReopenMs: Double
        let settingsRAM: MemorySnapshot
        let loc100kMs: Double
        let iconRenderCount: Int
        let iconRenderTotalMs: Double
        let iconRenderPerAppMs: Double
        let idleCPU_pct: Double
        let idleRAM: MemorySnapshot
    }

    // MARK: - Mach / POSIX probes

    static func memorySnapshot() -> MemorySnapshot {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        let mb = 1024.0 * 1024.0
        if kr == KERN_SUCCESS {
            return MemorySnapshot(
                physFootprintMB: (Double(info.phys_footprint) / mb * 100).rounded() / 100,
                rssMB: (Double(info.resident_size) / mb * 100).rounded() / 100
            )
        }
        return MemorySnapshot(physFootprintMB: 0, rssMB: 0)
    }

    static func processCPUMilliseconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let userMs = Double(usage.ru_utime.tv_sec) * 1000.0 + Double(usage.ru_utime.tv_usec) / 1000.0
        let sysMs = Double(usage.ru_stime.tv_sec) * 1000.0 + Double(usage.ru_stime.tv_usec) / 1000.0
        return userMs + sysMs
    }

    // MARK: - RunLoop Work & DisplayLink Pacing Recorder

    private final class FrameRecorder: NSObject {
        private var displayLink: CADisplayLink?
        private var lastTick: CFTimeInterval = 0
        private var frameIntervalsMs: [Double] = []
        private var workDurationsMs: [Double] = []
        private var turnStart: CFTimeInterval = 0
        private var observer: CFRunLoopObserver?
        private let maxHz: Int
        private var startTime: CFTimeInterval = 0
        private var startCPU: Double = 0

        init(maxHz: Int) {
            self.maxHz = max(60, maxHz)
            super.init()
        }

        func start() {
            frameIntervalsMs.removeAll(keepingCapacity: true)
            workDurationsMs.removeAll(keepingCapacity: true)
            lastTick = 0
            turnStart = CACurrentMediaTime()
            startTime = turnStart
            startCPU = PerformanceBenchmark.processCPUMilliseconds()

            let activities: CFRunLoopActivity = [.afterWaiting, .beforeWaiting]
            let obs = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, activities.rawValue, true, 0) { [weak self] _, activity in
                guard let self else { return }
                let now = CACurrentMediaTime()
                if activity == .afterWaiting {
                    self.turnStart = now
                } else if activity == .beforeWaiting {
                    if self.turnStart > 0 {
                        let dtMs = (now - self.turnStart) * 1000.0
                        if dtMs >= 0.05 && dtMs < 2000.0 {
                            self.workDurationsMs.append(dtMs)
                        }
                    }
                    self.turnStart = 0
                }
            }
            if let obs {
                CFRunLoopAddObserver(CFRunLoopGetMain(), obs, .commonModes)
                self.observer = obs
            }

            if let screen = NSScreen.main ?? NSScreen.screens.first {
                let link = screen.displayLink(target: self, selector: #selector(onDisplayLink(_:)))
                link.add(to: .main, forMode: .common)
                self.displayLink = link
            }
        }

        @objc private func onDisplayLink(_ link: CADisplayLink) {
            let ts = link.timestamp
            if lastTick > 0 {
                let dtMs = (ts - lastTick) * 1000.0
                if dtMs > 0.5 && dtMs < 1000.0 {
                    frameIntervalsMs.append(dtMs)
                }
            }
            lastTick = ts
        }

        func stop() -> FrameMetrics {
            let elapsed = max(0.001, CACurrentMediaTime() - startTime)
            let cpuDeltaMs = max(0, PerformanceBenchmark.processCPUMilliseconds() - startCPU)
            let cpuPct = (cpuDeltaMs / (elapsed * 1000.0)) * 100.0

            displayLink?.invalidate()
            displayLink = nil
            if let observer {
                CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
                self.observer = nil
            }

            let vsyncMs = 1000.0 / Double(maxHz)
            let dropped = frameIntervalsMs.filter { $0 > vsyncMs * 1.5 }.count
            let avgFPS = frameIntervalsMs.isEmpty ? 0 : min(Double(maxHz), 1000.0 / (frameIntervalsMs.reduce(0, +) / Double(frameIntervalsMs.count)))

            let sortedWork = workDurationsMs.sorted()
            func percentile(_ p: Double) -> Double {
                guard !sortedWork.isEmpty else { return 0 }
                let idx = min(sortedWork.count - 1, max(0, Int(Double(sortedWork.count - 1) * p)))
                return sortedWork[idx]
            }
            let within8 = sortedWork.isEmpty ? 100.0 : (Double(sortedWork.filter { $0 <= 8.33 }.count) / Double(sortedWork.count)) * 100.0
            let within16 = sortedWork.isEmpty ? 100.0 : (Double(sortedWork.filter { $0 <= 16.67 }.count) / Double(sortedWork.count)) * 100.0

            func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
            return FrameMetrics(
                durationSeconds: r2(elapsed),
                displayMaxHz: maxHz,
                displayFrames: frameIntervalsMs.count,
                displayFPS: r2(avgFPS),
                droppedFrames: dropped,
                workSamples: sortedWork.count,
                workP50Ms: r2(percentile(0.50)),
                workP95Ms: r2(percentile(0.95)),
                workMaxMs: r2(sortedWork.last ?? 0),
                within8_33msPct: r2(within8),
                within16_67msPct: r2(within16),
                cpuPct: r2(cpuPct)
            )
        }
    }

    // MARK: - Benchmark Execution

    static func run(delegate: AppDelegate, didFinishLaunchingMs: Double) {
        Task { @MainActor in
            let maxHz = NSScreen.main?.maximumFramesPerSecond ?? 60
            // 1. Wait 1.5s for startup tasks to settle
            try? await Task.sleep(for: .seconds(1.5))
            let startupCPU = processCPUMilliseconds()
            let startupRAM = memorySnapshot()

            // 2. First show latency
            let tShow0 = CACurrentMediaTime()
            delegate.launchpad.show()
            CATransaction.flush()
            try? await Task.sleep(for: .milliseconds(32))
            let firstShowMs = (CACurrentMediaTime() - tShow0) * 1000.0
            try? await Task.sleep(for: .milliseconds(500))
            let visibleRAM = memorySnapshot()

            // Warm reopen latency
            delegate.launchpad.hide()
            try? await Task.sleep(for: .milliseconds(450))
            let tReopen0 = CACurrentMediaTime()
            delegate.launchpad.show()
            CATransaction.flush()
            try? await Task.sleep(for: .milliseconds(32))
            let warmReopenMs = (CACurrentMediaTime() - tReopen0) * 1000.0
            try? await Task.sleep(for: .milliseconds(450))

            // 3. 120 Hz Swipe stress (2.0s)
            let vm = delegate.launchpad.viewModel
            let swipeRec = FrameRecorder(maxHz: maxHz)
            swipeRec.start()
            let steps = 240
            for i in 0..<steps {
                let phase = Double(i) / 60.0 * .pi
                vm.pageOffset = CGFloat(-abs(sin(phase)) * 360.0)
                try? await Task.sleep(for: .nanoseconds(8_333_333))
            }
            vm.pageOffset = 0
            vm.setPage(1)
            try? await Task.sleep(for: .milliseconds(250))
            vm.setPage(0)
            try? await Task.sleep(for: .milliseconds(250))
            let swipeMetrics = swipeRec.stop()

            // 4. Edit mode jiggle stress (2.0s)
            vm.setEditing(true)
            try? await Task.sleep(for: .milliseconds(100))
            let jiggleRec = FrameRecorder(maxHz: maxHz)
            jiggleRec.start()
            try? await Task.sleep(for: .seconds(2.0))
            let jiggleMetrics = jiggleRec.stop()
            vm.setEditing(false)
            try? await Task.sleep(for: .milliseconds(200))

            // 5. Widget Gallery open + live render (1.5s)
            let tGal0 = CACurrentMediaTime()
            vm.openWidgetGallery()
            CATransaction.flush()
            try? await Task.sleep(for: .milliseconds(32))
            let widgetGalleryOpenMs = (CACurrentMediaTime() - tGal0) * 1000.0
            let galRec = FrameRecorder(maxHz: maxHz)
            galRec.start()
            try? await Task.sleep(for: .seconds(1.5))
            let galMetrics = galRec.stop()
            let peakRAM = memorySnapshot()
            vm.showWidgetGallery = false
            try? await Task.sleep(for: .milliseconds(300))

            // 6. Settings first open & warm reopen
            let tSet0 = CACurrentMediaTime()
            delegate.openSettings()
            CATransaction.flush()
            try? await Task.sleep(for: .milliseconds(32))
            let settingsFirstOpenMs = (CACurrentMediaTime() - tSet0) * 1000.0
            try? await Task.sleep(for: .milliseconds(450))
            let settingsRAM = memorySnapshot()
            delegate.settings.close()
            try? await Task.sleep(for: .milliseconds(450))
            let tSet1 = CACurrentMediaTime()
            delegate.openSettings()
            CATransaction.flush()
            try? await Task.sleep(for: .milliseconds(32))
            let settingsReopenMs = (CACurrentMediaTime() - tSet1) * 1000.0
            try? await Task.sleep(for: .milliseconds(300))
            delegate.settings.close()
            try? await Task.sleep(for: .milliseconds(400))

            // 7. Microbenchmarks: loc() 100k + cold IconRenderer 10 apps
            let tLoc0 = CACurrentMediaTime()
            var locLen = 0
            for _ in 0..<100_000 {
                locLen &+= loc("settings.title").utf8.count
            }
            let loc100kMs = (CACurrentMediaTime() - tLoc0) * 1000.0
            _ = locLen

            let samplePaths = Array(delegate.store.catalog.keys.sorted().prefix(10))
            let tIcon0 = CACurrentMediaTime()
            let renderedCount = await Task.detached(priority: .userInitiated) {
                var ok = 0
                for path in samplePaths {
                    if IconRenderer.renderStyledHighResIcon(
                        for: path,
                        style: .clearLiquid,
                        tintRGB: (0.45, 0.42, 0.95),
                        isPro: true
                    ) != nil {
                        ok += 1
                    }
                }
                return ok
            }.value
            let iconRenderTotalMs = (CACurrentMediaTime() - tIcon0) * 1000.0
            let iconRenderPerAppMs = renderedCount > 0 ? iconRenderTotalMs / Double(renderedCount) : 0

            // 8. Hidden idle CPU & RAM (3.0s)
            delegate.launchpad.hide()
            try? await Task.sleep(for: .milliseconds(800))
            let idleT0 = CACurrentMediaTime()
            let idleCPU0 = processCPUMilliseconds()
            try? await Task.sleep(for: .seconds(3.0))
            let idleElapsed = max(0.001, CACurrentMediaTime() - idleT0)
            let idleCPUDelta = max(0, processCPUMilliseconds() - idleCPU0)
            let idleCPUPct = (idleCPUDelta / (idleElapsed * 1000.0)) * 100.0
            let idleRAM = memorySnapshot()

            func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
            let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            let report = Report(
                version: ver,
                displayMaxHz: maxHz,
                didFinishLaunchingMs: r2(didFinishLaunchingMs),
                startupCPU_ms: r2(startupCPU),
                startupRAM: startupRAM,
                firstShowMs: r2(firstShowMs),
                warmReopenMs: r2(warmReopenMs),
                visibleRAM: visibleRAM,
                swipe120Hz: swipeMetrics,
                jiggleEditMode: jiggleMetrics,
                widgetGalleryOpenMs: r2(widgetGalleryOpenMs),
                widgetGalleryMetrics: galMetrics,
                peakRAM: peakRAM,
                settingsFirstOpenMs: r2(settingsFirstOpenMs),
                settingsReopenMs: r2(settingsReopenMs),
                settingsRAM: settingsRAM,
                loc100kMs: r2(loc100kMs),
                iconRenderCount: renderedCount,
                iconRenderTotalMs: r2(iconRenderTotalMs),
                iconRenderPerAppMs: r2(iconRenderPerAppMs),
                idleCPU_pct: r2(idleCPUPct),
                idleRAM: idleRAM
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(report), let json = String(data: data, encoding: .utf8) {
                print("===PERF_JSON_BEGIN===")
                print(json)
                print("===PERF_JSON_END===")
            }
            exit(0)
        }
    }
}
