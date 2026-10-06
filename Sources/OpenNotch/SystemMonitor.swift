import Foundation
import Darwin

/// Per-core CPU load and memory use, sampled once a second only while something is
/// watching (`start()`/`stop()` are reference counted).
@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()
    static let historyLength = 36

    /// `cores[i]` is the load history (0...1, oldest first) of core i.
    @Published private(set) var cores: [[Double]] = []
    @Published private(set) var cpu: Double = 0
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryUsed: UInt64 = 0
    @Published private(set) var memoryHistory: [Double] = []
    let memoryTotal = ProcessInfo.processInfo.physicalMemory

    private var previousTicks: [[UInt32]] = []
    private var timer: Timer?
    private var watchers = 0

    private init() {}

    func start() {
        watchers += 1
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func stop() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
    }

    private func sampleCPU() {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        let ticks: [[UInt32]] = (0..<Int(count)).map { core in
            (0..<states).map { UInt32(bitPattern: info[core * states + $0]) }
        }
        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count else {
            cores = Array(repeating: [], count: ticks.count)
            return
        }

        var busySum = 0.0, totalSum = 0.0
        for (i, now) in ticks.enumerated() {
            let before = previousTicks[i]
            let delta = (0..<states).map { Double(now[$0] &- before[$0]) } // wraps safely
            let idle = delta[Int(CPU_STATE_IDLE)]
            let total = delta.reduce(0, +)
            let load = total > 0 ? (total - idle) / total : 0
            busySum += total - idle
            totalSum += total
            cores[i] = Array((cores[i] + [load]).suffix(Self.historyLength))
        }
        cpu = totalSum > 0 ? busySum / totalSum : 0
        cpuHistory = Array((cpuHistory + [cpu]).suffix(Self.historyLength))
    }

    /// "Memory Used" the way Activity Monitor counts it: app memory + wired + compressed.
    private func sampleMemory() {
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let ok = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard ok == KERN_SUCCESS else { return }
        let page = UInt64(vm_kernel_page_size)
        let app = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
        memoryUsed = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        memoryHistory = Array((memoryHistory + [Double(memoryUsed) / Double(memoryTotal)]).suffix(Self.historyLength))
    }
}
