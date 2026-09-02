//
//  CaptureMonitor.swift
//

import UIKit
import Combine

/// Reports whether the screen is being captured right now.
@MainActor
public final class CaptureMonitor: ObservableObject {

	public static let shared = CaptureMonitor()

	/// True while a capture is running: recording, AirPlay, or iPhone Mirroring.
	@Published public private(set) var isCapturing: Bool = false
	/// True while protected views are hidden: a capture, or the app not being active.
	@Published public private(set) var isHidingContent: Bool = false

	/// Best-effort guess at an iPhone Mirroring session. On by default: iOS does not
	/// report mirroring as a capture, so without it mirrored content is not protected
	/// at all. It is inferred from undocumented behaviour and may stop working on any
	/// iOS release. Set `false` to opt out.
	public var detectsMirroring: Bool = true {
		didSet {
			if !detectsMirroring { hasSeenMirroring = false }
			refresh()
		}
	}

	private var observers: [NSObjectProtocol] = []
	private let hiddenViews = NSHashTable<UIView>.weakObjects()
	private var hasSeenMirroring = false
	private var isActive = true
	private var displayStatus: DarwinNotification?

	private init() {
		isActive = UIApplication.shared.applicationState == .active

		let names: [Notification.Name] = [
			UIScreen.capturedDidChangeNotification,
			UIScreen.brightnessDidChangeNotification,
			UIApplication.didBecomeActiveNotification,
			UIApplication.willResignActiveNotification,
			UIApplication.willEnterForegroundNotification,
			UIApplication.didEnterBackgroundNotification
		]
		observers = names.map { name in
			NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
				MainActor.assumeIsolated {
					guard let self else { return }
					switch name {
					case UIApplication.didBecomeActiveNotification:
						self.isActive = true
					case UIApplication.willResignActiveNotification,
						 UIApplication.didEnterBackgroundNotification:
						self.isActive = false
					default:
						break
					}
					if name == UIApplication.didEnterBackgroundNotification {
						self.hasSeenMirroring = false
					}
					self.refresh()
				}
			}
		}
		displayStatus = DarwinNotification("com.apple.iokit.hid.displayStatus") { [weak self] in
			MainActor.assumeIsolated { self?.refresh() }
		}

		refresh()
	}

	func hideWhileCapturing(_ view: UIView) {
		hiddenViews.add(view)
		view.alpha = isHidingContent ? 0 : 1
	}

	public func refresh() {
		if detectsMirroring && looksLikeMirroring() {
			hasSeenMirroring = true
		}
		let capturing = isSystemCapturing || (detectsMirroring && hasSeenMirroring)
		let hiding = capturing || !isActive

		if capturing != isCapturing {
			isCapturing = capturing
		}
		guard hiding != isHidingContent else { return }
		isHidingContent = hiding
		for view in hiddenViews.allObjects {
			view.alpha = hiding ? 0 : 1
		}
	}

	/// Set by recording, AirPlay and Mac-side screen recording. Not by iPhone Mirroring.
	/// Asks every screen rather than picking one: `connectedScenes` is unordered, at
	/// launch no scene is foregroundActive yet, and mirroring can add a screen.
	private var isSystemCapturing: Bool {
		windowScenes.contains { $0.screen.isCaptured }
	}

	private func looksLikeMirroring() -> Bool {
		#if targetEnvironment(simulator)
		return false
		#else
		guard isActive else { return false }
		if let isDisplayOn = displayStatus?.state { return isDisplayOn == 0 }
		return (activeScreen?.brightness ?? 1) <= 0.001
		#endif
	}

	private var activeScreen: UIScreen? {
		let scenes = windowScenes
		return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
	}

	private var windowScenes: [UIWindowScene] {
		UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
	}
}
