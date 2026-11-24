# Crumbs

Crumbs is a free, open-source macOS launcher. The current release scope is installed application search. Planned features include commands, files, quicklinks, System Settings search, snippets, emoji, a calculator, clipboard history, Raycast extensions, integrations with the user's preferred tools, and local or hosted AI providers.

## Current launcher

- While Crumbs is running, Control-Shift-Space toggles the launcher. Typing filters apps by name, the arrow keys change selection, and Return opens the selected app. Escape restores focus to the previous app. An outside click dismisses the panel and reaches the clicked app.
- App discovery runs off the main actor when the launcher opens. It scans standard Applications folders and Safari's system cryptex, deduplicates by resolved URL, and sorts by display name.
- AppKit owns the floating panel and search field. SwiftUI draws separate blurred search and results surfaces with a 40% scrim and matching inverted ink ramps for Light and Dark. An 8 pt transparent gap separates the surfaces. The footer overlays the fading list. Liquid Glass controls place Settings on the left and Open on the right. The opening animation respects Reduce Motion, and the backdrop respects Reduce Transparency.
- Settings displays the fixed launcher shortcut. The app delegate registers it with the system at launch.

## Project Rules

Keep the implementation direct and proportionate to the task. Prefer clear ownership, focused changes, and modern Apple APIs supported by the project's deployment target and toolchain.

Do not assume a UI framework, minimum macOS version, build system, dependency policy, or feature set. Record those choices when they are confirmed.

Prefer modern Apple APIs for new code and complete strict concurrency is required. Prefer the latest Swift 6+ patterns and modern Apple APIs. Use `@Observable` for SwiftUI model observation and `SMAppService` for launch at login. Older APIs are not automatically unsupported; use them when a concrete integration requirement justifies the choice. Check APIs and language features against the SDK and compiler used locally and in CI. Crumbs supports macOS 26 and later. Guard APIs that require newer releases with explicit availability checks and preserve the supported baseline.

## Structure

| Path                          | Purpose                                                                     |
| ----------------------------- | --------------------------------------------------------------------------- |
| `Crumbs/Crumbs/App/`          | App entry point, lifecycle, global shortcut, and Settings scene             |
| `Crumbs/Crumbs/Launcher/`     | Floating panel, search field, and results UI                                |
| `Crumbs/Crumbs/AppDiscovery/` | Find installed application bundles for launcher results                     |
| `Crumbs/Crumbs/DesignSystem/` | Shared visual values in Theme.swift                                         |
| `Tests/`                      | Swift Testing suites in Tests/{feature name}/, mirroring the source folders |

Place each feature directly under `Crumbs/Crumbs/{feature name}/` and its suites under `Tests/{feature name}/`. Update this map as application source and tooling are added. Create directories and architectural layers when the implementation needs them.

## Build and verify

Use Xcode 27 with the Crumbs scheme and My Mac destination. Press Command-R to run the app. From the repository root:

```sh
xcodebuild -project Crumbs/Crumbs.xcodeproj -scheme Crumbs -destination 'platform=macOS' build
swift test
```

Swift Testing runs the application catalog and launcher search suites without launching Crumbs. To run a single suite, use `swift test --filter ApplicationCatalogTests`. Verify panel layout, keyboard focus, hotkey toggling, outside clicks, and app launching manually.

## Implementation rules

- Keep changes focused on the requested outcome. Avoid unrelated refactors and speculative features.
- Read the surrounding code before introducing a new pattern. Follow established conventions unless the task requires changing them.
- Give long-lived state a clear owner. Introduce abstractions for concrete responsibilities or repeated use.
- Keep blocking work off the UI thread.
- For asynchronous work, define ownership, cancellation, and handling of stale results.
- Verify API availability against the selected SDK, compiler, and deployment target.
- Add dependencies for a concrete need and record the rationale.
- Keep comments useful and concise. Explain a constraint or decision when the code alone cannot.
- Document the source and regeneration command for generated files. Edit their source rather than generated output.

## macOS behavior

- Request system permissions when an implemented feature needs them, with a clear user-facing explanation.
- Handle denied or revoked permissions without crashing or repeatedly prompting.
- Keep keyboard focus, shortcuts, window behavior, and application lifecycle explicit and predictable.
- Verify interface changes in the running app when possible. State when visual or interaction checks could not be performed.

## Repository hygiene

- Keep secrets, signing credentials, build outputs, and per-user Xcode state out of version control.
- Do not discard, overwrite, or revert unrelated work.
- Do not commit or push unless requested.
- Keep setup instructions reproducible and document required tools.

## Documentation and decisions

Keep `docs/{feature_name}.md` concise and accurate. Update it in the same change when requirements, architecture, setup instructions, or milestones change.

Record:

- Confirmed requirements.
- Significant decisions and their rationale.
- The current implementation state.
- Known limitations and unfinished work, each with a concrete next step.
- Available build, run, and verification commands.

Add detailed documents when needed and link them from the context document. Avoid documenting proposed architecture as implemented behavior.

## Before finishing

- Review the diff for accidental changes and preservation of existing work.
- Run relevant available build, test, and static checks.
- Use checks appropriate to the change; do not invent commands or claim checks passed without running them.
- Fix documentation made inaccurate by the change.
- Report what changed, what was verified, and what remains unverified.
- If blocked, explain the concrete blocker and the next step needed to resolve it.
