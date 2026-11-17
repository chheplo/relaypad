import SwiftUI
import UIKit

/// UIKit delivers individual finger lifetimes even when a second key or the pad is in use.
struct PressSurface: UIViewRepresentable {
    var onChange: (Bool) -> Void

    func makeUIView(context: Context) -> PressView { PressView() }
    func updateUIView(_ view: PressView, context: Context) { view.onChange = onChange }
    static func dismantleUIView(_ view: PressView, coordinator: ()) { view.finish() }

    final class PressView: UIView {
        var onChange: ((Bool) -> Void)?
        private var finger: UITouch?
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard finger == nil, let touch = touches.first else { return }
            finger = touch
            onChange?(true)
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish() }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish() }
        func finish() {
            guard finger != nil else { return }
            finger = nil
            onChange?(false)
        }
    }
}

struct TrackSurface: UIViewRepresentable {
    var sensitivity: Double
    var haptics: Bool
    var send: (RemoteEvent) -> Void

    func makeUIView(context: Context) -> TrackView { TrackView() }
    func updateUIView(_ view: TrackView, context: Context) {
        view.sensitivity = sensitivity
        view.haptics = haptics
        view.send = send
    }
    static func dismantleUIView(_ view: TrackView, coordinator: ()) { view.cancel() }

    final class TrackView: UIView {
        var sensitivity = 1.4
        var haptics = true
        var send: ((RemoteEvent) -> Void)?
        private var fingers: Set<UITouch> = []
        private var origin = CGPoint.zero
        private var previous = CGPoint.zero
        private var startTime = 0.0
        private var touchedWithTwo = false
        private var moved = false
        private var dragged = false
        private var suppressed = false
        private var holdTimer: Timer?
        private let feedback = UIImpactFeedbackGenerator(style: .light)
        private let touchSpot = CALayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            touchSpot.bounds = CGRect(x: 0, y: 0, width: 34, height: 34)
            touchSpot.cornerRadius = 17
            touchSpot.borderWidth = 1
            touchSpot.borderColor = UIColor(red: 1, green: 0.72, blue: 0.38, alpha: 0.9).cgColor
            touchSpot.backgroundColor = UIColor(red: 1, green: 0.72, blue: 0.38, alpha: 0.14).cgColor
            touchSpot.opacity = 0
            layer.addSublayer(touchSpot)
        }
        required init?(coder: NSCoder) { nil }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            if fingers.isEmpty {
                startTime = ProcessInfo.processInfo.systemUptime
                touchedWithTwo = false
                moved = false
                suppressed = false
            }
            fingers.formUnion(touches)
            holdTimer?.invalidate()
            if fingers.count > 2 {
                endDrag()
                suppressed = true
            } else if fingers.count == 2 {
                if dragged { suppressed = true }
                endDrag()
                touchedWithTwo = true
            } else if !suppressed {
                let timer = Timer(timeInterval: 0.42, repeats: false) { [weak self] _ in self?.beginDrag() }
                RunLoop.main.add(timer, forMode: .common)
                holdTimer = timer
            }
            origin = midpoint()
            previous = origin
            markTouch(at: origin)
            if haptics { feedback.prepare() }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard !suppressed, !fingers.isEmpty, !(touchedWithTwo && fingers.count == 1) else { return }
            let point = midpoint()
            markTouch(at: point)
            if hypot(point.x - origin.x, point.y - origin.y) > 3 {
                moved = true
                holdTimer?.invalidate()
            }
            guard moved || dragged else { return }
            let dx = Double(point.x - previous.x)
            let dy = Double(point.y - previous.y)
            previous = point
            guard dx != 0 || dy != 0 else { return }
            if fingers.count == 2 {
                send?(.scroll(dx: dx * 1.7, dy: dy * 1.7))
            } else {
                send?(.move(dx: dx * sensitivity, dy: dy * sensitivity))
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            holdTimer?.invalidate()
            fingers.subtract(touches)
            if fingers.isEmpty {
                if dragged {
                    endDrag()
                } else if !suppressed, !moved, !touchedWithTwo, ProcessInfo.processInfo.systemUptime - startTime < 0.42 {
                    send?(.click(button: .left, count: 1))
                    if haptics { feedback.impactOccurred(intensity: 0.55) }
                }
                touchSpot.opacity = 0
            } else if touchedWithTwo {
                // A trailing finger belongs to the scroll gesture until all fingers lift.
                suppressed = true
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancel() }
        func cancel() {
            holdTimer?.invalidate()
            endDrag()
            fingers.removeAll()
            suppressed = true
            touchSpot.opacity = 0
        }

        private func midpoint() -> CGPoint {
            guard !fingers.isEmpty else { return .zero }
            let total = fingers.reduce(CGPoint.zero) { sum, touch in
                let p = touch.location(in: self)
                return CGPoint(x: sum.x + p.x, y: sum.y + p.y)
            }
            return CGPoint(x: total.x / CGFloat(fingers.count), y: total.y / CGFloat(fingers.count))
        }

        private func beginDrag() {
            guard fingers.count == 1, !touchedWithTwo, !moved, !suppressed else { return }
            dragged = true
            send?(.button(button: .left, down: true))
            if haptics { feedback.impactOccurred() }
        }

        private func endDrag() {
            if dragged { send?(.button(button: .left, down: false)) }
            dragged = false
        }

        private func markTouch(at point: CGPoint) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            touchSpot.position = point
            touchSpot.opacity = 1
            CATransaction.commit()
        }
    }
}
