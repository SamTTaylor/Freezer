//
// Created by Sergey on 07/05/16.
//
// Updated for Clutter by andrewtenno on 10/4/17

import Foundation

private func _Selector(_ str: String) -> Selector {
    // Now Xcode can fuck off with his suggestion to use #selector
    return Selector(str)
}

enum StartingPoint: Equatable {
    case fixed(NSDate)
    case offset(TimeInterval)
}

func == (lhs: StartingPoint, rhs: StartingPoint) -> Bool {
    switch (lhs, rhs) {
    case (.fixed(let lvalue), .fixed(let rvalue)) where lvalue == rvalue: return true
    case (.offset(let lvalue), .offset(let rvalue)) where lvalue == rvalue: return true
    default: return false
    }
}

extension NSDate {
    func newInit() -> NSDate {
        return now()
    }

    func newInitWithTimeIntervalSinceNow(timeIntervalSinceNow secs: TimeInterval) -> NSDate {
        return NSDate(timeInterval: secs, since: now() as Date)
    }

    convenience init(timeIntervalSinceRealNow secs: TimeInterval) {
        // After we swizzle initWithTimeIntervalSinceNow: this method is only way to obtain real date
        self.init(timeIntervalSinceNow: secs)
    }

    private func now() -> NSDate {
        let startingPoint = Freezer.startingPoints.last!
        switch startingPoint {
        case .fixed(let date): return date
        case .offset(let interval): return NSDate(timeIntervalSinceRealNow: interval)
        }
    }
}

public class Freezer {
    private static var oldNSDateInit: IMP!
    private static var oldNSDateInitWithTimeIntervalSinceNow: IMP!

    fileprivate static var startingPoints: [StartingPoint] = []

    let startingPoint: StartingPoint

    private(set) var running: Bool = false

    public init(to: NSDate) {
        self.startingPoint = .fixed(to)
    }

    public init(from: NSDate) {
        let now = NSDate(timeIntervalSinceRealNow: 0)
        self.startingPoint = .offset(from.timeIntervalSince1970 - now.timeIntervalSince1970)
    }

    deinit {
        if running {
            stop()
        }
    }

    public func start() {
        guard !running else {
            return
        }

        running = true

        if Freezer.startingPoints.count == 0 {
            Freezer.oldNSDateInit = replaceImplementation(oldSelector: _Selector("init"), newSelector: _Selector("newInit"))
            Freezer.oldNSDateInitWithTimeIntervalSinceNow =
                    replaceImplementation(oldSelector: _Selector("initWithTimeIntervalSinceNow:"),
                                          newSelector: _Selector("newInitWithTimeIntervalSinceNow:"))

            let initWithRealNow = class_getInstanceMethod(NSClassFromString("__NSPlaceholderDate"),
                                                          _Selector("initWithTimeIntervalSinceRealNow:"))
            method_setImplementation(initWithRealNow, Freezer.oldNSDateInitWithTimeIntervalSinceNow)
        }

        Freezer.startingPoints.append(startingPoint)
    }

    public func stop() {
        guard running else {
            return
        }

        for (idx, point) in Freezer.startingPoints.enumerated().reversed() {
            if point == self.startingPoint {
                Freezer.startingPoints.remove(at: idx)
                break
            }
        }

        if Freezer.startingPoints.count == 0 {
            restoreImplementation(selector: _Selector("init"), oldImplementation: Freezer.oldNSDateInit)
            restoreImplementation(selector: _Selector("initWithTimeIntervalSinceNow:"), oldImplementation: Freezer.oldNSDateInitWithTimeIntervalSinceNow)
        }

        running = false
    }

    private func replaceImplementation(oldSelector: Selector, newSelector: Selector) -> IMP {
        let oldMethod = class_getInstanceMethod(NSClassFromString("__NSPlaceholderDate"), oldSelector)
        let oldImplementation = method_getImplementation(oldMethod)

        let newMethod = class_getInstanceMethod(NSDate.self, newSelector)
        let newImplementation = method_getImplementation(newMethod)

        method_setImplementation(oldMethod, newImplementation)

        return oldImplementation!
    }

    private func restoreImplementation(selector: Selector, oldImplementation: IMP) {
        let method = class_getInstanceMethod(NSClassFromString("__NSPlaceholderDate"), selector)
        method_setImplementation(method, oldImplementation)
    }
}

public func freeze(time: NSDate, block: () -> ()) {
    let freezer = Freezer(to: time)
    freezer.start()
    block()
    freezer.stop()
}

public func timeshift(from: NSDate, block: () -> ()) {
    let freezer = Freezer(from: from)
    freezer.start()
    block()
    freezer.stop()
}
