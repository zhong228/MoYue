import QuartzCore

/// How fast tapped page turns play while the reader is tapping quickly.
///
/// Until 2026-09-30 each turn's speed was the last gap between two taps and
/// nothing else, and only turns that had not started yet took it: the first turn
/// of a burst played out in full at 1×, and the one queued behind it started at
/// up to 3× — one slow turn, then abruptly fast ones. Two things fix that, and
/// both live here:
///
/// - **The speed ramps.** Each tap moves the speed part of the way towards what
///   the tapping rhythm asks for, so a burst winds up over a few turns (1× → 1.9×
///   → 2.4× …) and winds down the same way when the tapping slows.
/// - **The turn already on screen speeds up too** (`ReaderTurnLayerClock`), the
///   moment the next tap lands, instead of being waited out at its old speed.
struct ReaderTurnBurstPacer {
    /// A turn's duration at 1×. Tapping at this rhythm asks for 1×; tapping twice
    /// as often asks for 2×.
    static let naturalTurnDuration: CFTimeInterval = 0.28
    static let maximumSpeed: Float = 3
    /// How much of the gap between the current speed and the rhythm's speed one
    /// tap closes. 1 would be the old behaviour: the full jump on the next turn.
    static let rampFraction: Float = 0.5
    /// A gap this long is no longer the same burst: the next turn is a lone turn
    /// and plays at 1×.
    static let pauseDuration: CFTimeInterval = 0.6

    private(set) var speed: Float = 1
    private var lastTapTime: CFTimeInterval?

    /// Registers a tapped turn and returns the speed turns should now play at.
    @discardableResult
    mutating func registerTap(at now: CFTimeInterval) -> Float {
        defer { lastTapTime = now }
        guard let lastTapTime else {
            speed = 1
            return speed
        }
        let gap = now - lastTapTime
        guard gap < Self.pauseDuration else {
            speed = 1
            return speed
        }
        // Two commands in the same instant (a held volume key): as fast as it goes.
        let rhythm = gap > 0.0001
            ? min(max(Float(Self.naturalTurnDuration / gap), 1), Self.maximumSpeed)
            : Self.maximumSpeed
        speed += (rhythm - speed) * Self.rampFraction
        return speed
    }
}

/// Changes how fast the animations under a layer run, while they run.
///
/// Setting `CALayer.speed` alone rescales the layer's whole clock, so an
/// animation in flight jumps to a different point of its timeline. Re-basing the
/// clock at the moment of the change keeps every animation exactly where it is
/// and only changes how fast it goes on from there.
enum ReaderTurnLayerClock {
    static func setSpeed(_ speed: Float, on layer: CALayer, at now: CFTimeInterval = CACurrentMediaTime()) {
        let localNow = layer.convertTime(now, from: nil)
        let parentNow = layer.superlayer?.convertTime(now, from: nil) ?? now
        layer.timeOffset = localNow
        layer.beginTime = parentNow
        layer.speed = speed
    }

    /// Back to the parent's clock. Only once nothing under the layer is animating:
    /// the layer's time moves, and a running animation would move with it.
    static func reset(_ layer: CALayer) {
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
    }
}
