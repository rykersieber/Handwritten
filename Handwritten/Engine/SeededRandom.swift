import Foundation

/// Fast, seedable random generator (SplitMix64). Same seed → same sequence.
struct RNG {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    init() { self.init(seed: UInt64.random(in: 0...UInt64.max)) }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// 0 ..< 1
    mutating func double() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func chance(_ p: Double) -> Bool { p > 0 && double() < p }

    mutating func range(_ a: Double, _ b: Double) -> Double {
        let lo = min(a, b), hi = max(a, b)
        return lo + (hi - lo) * double()
    }

    mutating func int(_ a: Int, _ b: Int) -> Int {
        let lo = min(a, b), hi = max(a, b)
        if lo == hi { return lo }
        return lo + Int(next() % UInt64(hi - lo + 1))
    }

    mutating func pick<T>(_ arr: [T]) -> T? {
        arr.isEmpty ? nil : arr[int(0, arr.count - 1)]
    }

    /// Standard normal (Box–Muller).
    mutating func normal() -> Double {
        let u1 = max(double(), 1e-12), u2 = double()
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }

    /// Multiplier with mean ≈ 1 whose spread is controlled by `amount` (0...1.5).
    mutating func variation(_ amount: Double, distribution: String) -> Double {
        guard amount > 0 else { return 1 }
        switch distribution {
        case "gaussian":
            return max(0.25, 1 + normal() * amount * 0.5)
        case "uniform":
            return max(0.25, 1 + (double() * 2 - 1) * amount * 0.8)
        default:
            let sigma = amount * 0.6
            return exp(sigma * normal() - sigma * sigma / 2)
        }
    }

    /// Weighted pick of an index.
    mutating func weighted(_ weights: [Double]) -> Int {
        let total = weights.reduce(0) { $0 + max(0, $1) }
        guard total > 0 else { return 0 }
        var r = double() * total
        for (i, w) in weights.enumerated() {
            r -= max(0, w)
            if r < 0 { return i }
        }
        return weights.count - 1
    }
}
