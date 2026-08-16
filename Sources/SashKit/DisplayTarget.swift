import Foundation
import CoreGraphics

/// Which display a per-monitor preference should act on right now.
///
/// The point is that *asking* for a display and *having* it are separate facts. A monitor that
/// sleeps, gets unplugged, or drops off a KVM should pause the feature pinned to it, not cancel
/// it, so the choice is remembered while the display is away and resumes on its own when it
/// comes back. Pure, so the rule is testable without a window server.
public enum DisplayTarget {

    /// The display to act on: the one the user chose, but only while it is actually attached.
    /// Nil means "act on nothing for now", which is deliberately indistinguishable at the call
    /// site from having chosen nothing. The difference lives in the stored preference, not here.
    public static func active(desired: CGDirectDisplayID?,
                              attached: [CGDirectDisplayID]) -> CGDirectDisplayID? {
        guard let desired, attached.contains(desired) else { return nil }
        return desired
    }
}
