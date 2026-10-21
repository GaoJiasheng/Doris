import Foundation
import SwiftUI
import Combine
import DorisUI

/// How often the avatar reacts to task events and notifications.
public enum AvatarActivityLevel: String, CaseIterable {
    case quiet    = "quiet"    // one-shots only on direct user interaction
    case standard = "standard" // reactions on task completion + agent banners (default)
    case lively   = "lively"   // reactions on every event
}

/// Where the avatar lives: docked to a screen edge (the notch / menu-bar
/// tab — default), or as a free-floating animated desktop pet that sits
/// above all windows and can be dragged anywhere.
public enum AvatarPlacement: String, CaseIterable {
    case edge    = "edge"
    case desktop = "desktop"
}

/// Desktop-pet render size. Value is the character's width in points; the
/// height follows the animation clip's ~1:1.5 aspect.
public enum PetSize: String, CaseIterable {
    case small  = "small"
    case medium = "medium"
    case large  = "large"

    public var width: CGFloat {
        switch self {
        case .small:  return 110
        case .medium: return 140
        case .large:  return 180
        }
    }
}

/// The character's settings: how lively it is, where it lives (the notch
/// / menu-bar logo or a desktop pet), and the pet's size and position.
@MainActor
final class AvatarSettings: ObservableObject {
    static let shared = AvatarSettings()

    @Published var activityLevel: AvatarActivityLevel {
        didSet { UserDefaults.standard.set(activityLevel.rawValue, forKey: Self.activityKey) }
    }

    /// Edge-docked (default) vs free-floating desktop pet.
    @Published var placement: AvatarPlacement {
        didSet { UserDefaults.standard.set(placement.rawValue, forKey: Self.placementKey) }
    }

    /// Desktop-pet size (only meaningful when `placement == .desktop`).
    @Published var petSize: PetSize {
        didSet { UserDefaults.standard.set(petSize.rawValue, forKey: Self.petSizeKey) }
    }

    private static let activityKey   = "doris.avatar.activityLevel"
    private static let placementKey  = "doris.avatar.placement"
    private static let petSizeKey    = "doris.avatar.petSize"
    private static let petPosXKey    = "doris.avatar.petPosition.x"
    private static let petPosYKey    = "doris.avatar.petPosition.y"

    /// Last desktop-pet window origin (bottom-left, screen coords). nil until
    /// the user has placed it once. Persisted directly (not @Published) since
    /// the pet controller writes it on every drag.
    var petPosition: CGPoint? {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: Self.petPosXKey) != nil,
                  d.object(forKey: Self.petPosYKey) != nil else { return nil }
            return CGPoint(x: d.double(forKey: Self.petPosXKey),
                           y: d.double(forKey: Self.petPosYKey))
        }
        set {
            let d = UserDefaults.standard
            if let p = newValue {
                d.set(p.x, forKey: Self.petPosXKey)
                d.set(p.y, forKey: Self.petPosYKey)
            } else {
                d.removeObject(forKey: Self.petPosXKey)
                d.removeObject(forKey: Self.petPosYKey)
            }
        }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.activityKey),
           let level = AvatarActivityLevel(rawValue: raw) {
            self.activityLevel = level
        } else {
            self.activityLevel = .standard
        }
        if let raw = UserDefaults.standard.string(forKey: Self.placementKey),
           let p = AvatarPlacement(rawValue: raw) {
            self.placement = p
        } else {
            self.placement = .edge
        }
        if let raw = UserDefaults.standard.string(forKey: Self.petSizeKey),
           let s = PetSize(rawValue: raw) {
            self.petSize = s
        } else {
            self.petSize = .medium
        }
    }

    /// Fire a task-completion celebration, respecting the activity level.
    /// Quiet mode never auto-celebrates; standard/lively always do.
    func celebrateTaskDone() {
        guard activityLevel != .quiet else { return }
        HeroEvents.shared.celebrate()
    }

    /// Fire an alert reaction (agent notification arrived). Suppressed in quiet mode.
    func alertIfAllowed() {
        guard activityLevel != .quiet else { return }
        HeroEvents.shared.alert()
    }
}
