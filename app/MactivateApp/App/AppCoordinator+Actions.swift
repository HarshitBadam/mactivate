import AppKit
import MactivateRuntime

extension AppCoordinator {
    func makeSettingsActions() -> SettingsActions {
        SettingsActions(
            setSpatialTapBinding: { [weak self] identifier, gesture in
                self?.setSpatialTapBinding(identifier, gesture: gesture)
            },
            setSpatialTapDispatchEnabled: { [weak self] enabled in
                self?.setSpatialTapDispatchEnabled(enabled)
            },
            setPanelHintsEnabled: { [weak self] enabled in
                self?.setPanelHintsEnabled(enabled)
            },
            setQuickAction: { [weak self] index, identifier in
                self?.setQuickAction(index: index, identifier: identifier)
            },
            addApplication: { [weak self] in
                self?.addApplication() ?? false
            },
            addWebURL: { [weak self] name, value in
                self?.addWebURL(name: name, value: value) ?? false
            },
            addShortcut: { [weak self] name in
                self?.addShortcut(name: name) ?? false
            },
            deleteAction: { [weak self] identifier in
                self?.deleteAction(identifier)
            },
            refreshShortcuts: { [weak self] in
                self?.refreshShortcuts(surfaceAsActionError: true)
            },
            setLaunchAtLogin: { [weak self] enabled in
                self?.setLaunchAtLoginEnabled(enabled)
            },
            beginCalibrationCapture: { [weak self] target in
                self?.beginCalibrationCapture(target)
            },
            stopCalibrationCapture: { [weak self] in
                self?.state.tapCalibrationTarget = nil
            },
            saveCalibration: { [weak self] in
                self?.saveCalibration()
            },
            resetCalibration: { [weak self] in
                self?.resetCalibration()
            },
            beginRegionCalibration: { [weak self] in
                self?.beginRegionCalibration()
            },
            stopRegionCalibration: { [weak self] in
                self?.state.tapRegionCalibrationTarget = nil
            },
            saveRegionCalibration: { [weak self] in
                self?.saveRegionCalibration()
            },
            resetRegionCalibration: { [weak self] in
                self?.resetRegionCalibration()
            },
            testAction: { [weak self] identifier in
                guard let self, let action = self.state.action(for: identifier) else {
                    return
                }
                self.perform(action, invocation: .quickAction)
            },
            reset: { [weak self] in self?.resetSettings() }
        )
    }

    func setSpatialTapBinding(
        _ identifier: ActionIdentifier?,
        gesture: PalmTapGesture
    ) {
        do {
            try runtime.setSpatialTapBinding(identifier, for: gesture)
            state.configuration = runtime.currentConfiguration
            refreshStatusItem()
        } catch {
            state.recentWarning = error.localizedDescription
        }
    }

    func setSpatialTapDispatchEnabled(_ enabled: Bool) {
        do {
            try runtime.setSpatialTapDispatchEnabled(enabled)
            state.configuration = runtime.currentConfiguration
            refreshStatusItem()
        } catch {
            state.recentWarning = error.localizedDescription
        }
    }

    func setPanelHintsEnabled(_ enabled: Bool) {
        do {
            try runtime.setPanelHintsEnabled(enabled)
            state.configuration = runtime.currentConfiguration
            refreshStatusItem()
        } catch {
            state.recentWarning = error.localizedDescription
        }
    }

    func setQuickAction(index: Int,
                        identifier: ActionIdentifier?) {
        guard (0..<AppPreferences.quickActionCount).contains(index) else {
            return
        }
        var updated = state.preferences
        updated.quickActionIDs = updated.normalizedQuickActionIDs
        updated.quickActionIDs[index] = identifier
        savePreferences(updated)
        if state.settingsFocusedSlot == index {
            state.settingsFocusedSlot = nil
        }
    }

    @discardableResult
    func addApplication() -> Bool {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.application]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.prompt = "Add Application"
        guard openPanel.runModal() == .OK else { return false }
        guard let url = openPanel.url,
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier else {
            state.actionError = "The selected application has no bundle identifier."
            return false
        }
        let name = bundle.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String ?? bundle.object(
            forInfoDictionaryKey: "CFBundleName"
        ) as? String ?? url.deletingPathExtension().lastPathComponent
        return addAction(
            .application(name: name, bundleIdentifier: identifier)
        )
    }

    @discardableResult
    func addWebURL(name: String, value: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanValue) else {
            state.actionError = AppActionError.invalidURL.localizedDescription
            return false
        }
        let action = AppActionDefinition.webURL(name: cleanName, url: url)
        guard action.isValid else {
            state.actionError = AppActionError.invalidURL.localizedDescription
            return false
        }
        return addAction(action)
    }

    @discardableResult
    func addShortcut(name: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = AppActionDefinition.shortcut(name: cleanName)
        guard action.isValid else {
            state.actionError = "Enter a Shortcut name."
            return false
        }
        return addAction(action)
    }

    @discardableResult
    private func addAction(_ action: AppActionDefinition) -> Bool {
        var updated = state.preferences
        updated.actions.append(action)
        if let emptyIndex = updated.normalizedQuickActionIDs.firstIndex(where: {
            $0 == nil
        }) {
            updated.quickActionIDs = updated.normalizedQuickActionIDs
            updated.quickActionIDs[emptyIndex] = action.id
        }
        if savePreferences(updated) {
            state.actionError = nil
            return true
        }
        return false
    }

    func deleteAction(_ identifier: ActionIdentifier) {
        var updated = state.preferences
        updated.actions.removeAll { $0.id == identifier }
        updated.quickActionIDs = updated.normalizedQuickActionIDs.map {
            $0 == identifier ? nil : $0
        }
        guard savePreferences(updated) else { return }

        for gesture in PalmTapGesture.allCases
        where state.configuration.spatialTapBindings[gesture] == identifier {
            setSpatialTapBinding(nil, gesture: gesture)
        }
    }

    @discardableResult
    private func savePreferences(_ preferences: AppPreferences) -> Bool {
        do {
            try preferencesStore.save(preferences)
            state.preferences = preferences
            return true
        } catch {
            state.recentWarning = error.localizedDescription
            state.actionError = error.localizedDescription
            return false
        }
    }

    func refreshShortcuts(surfaceAsActionError: Bool = false) {
        executor.listShortcuts { [weak self] result in
            switch result {
            case .success(let names):
                self?.state.availableShortcuts = names
                if surfaceAsActionError {
                    self?.state.actionError = nil
                }
            case .failure(let error):
                self?.state.recentWarning = error.localizedDescription
                if surfaceAsActionError {
                    self?.state.actionError = error.localizedDescription
                }
            }
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
        } catch {
            state.recentWarning = error.localizedDescription
        }
        state.launchAtLoginStatus = launchAtLogin.status
        refreshStatusItem()
    }

    func resetSettings() {
        do {
            try runtime.resetConfiguration()
            state.configuration = runtime.currentConfiguration
        } catch {
            state.recentWarning = error.localizedDescription
        }
        var defaults = AppPreferences.default
        defaults.onboardingCompleted = true
        if savePreferences(defaults) {
            state.actionError = nil
        }
        refreshStatusItem()
    }

    func completeOnboarding() {
        var updated = state.preferences
        updated.onboardingCompleted = true
        if savePreferences(updated) {
            onboardingWindowController?.close()
        }
    }
}
