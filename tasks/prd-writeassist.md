[PRD]
# PRD: WriteAssist (macOS MVP)

## Overview

WriteAssist is a lightweight macOS desktop writing assistant that detects and suggests corrections for spelling and basic grammar issues. It uses Apple's native `NSSpellChecker` for both spelling and grammar detection, runs entirely offline with no backend, and targets macOS 15 Sequoia. The app provides a single-window SwiftUI interface with a text editor and a collapsible bottom panel listing all detected issues.

## Goals

- Deliver a native macOS writing assistant using SwiftUI and `NSSpellChecker`
- Detect spelling errors (red underline) and basic grammar issues (blue underline) in English text
- Auto-check text after ~1 second of typing idle (debounced)
- Provide inline suggestion popovers and a collapsible issues panel
- Maintain sub-2-second check performance for ~1,000 words
- Ship as an SPM-based project buildable with `swift build`

## Quality Gates

These commands must pass for every user story:
- `swift build` - Project compiles without errors
- `swiftlint` - No linting violations

## User Stories

### US-001: Initialize SPM project with SwiftUI app scaffold
**Description:** As a developer, I want a working SPM-based macOS app scaffold so that the project builds and launches an empty window.

**Acceptance Criteria:**
- [ ] `Package.swift` configured for macOS 15 with SwiftUI dependency
- [ ] App entry point using `@main` and `SwiftUI.App` protocol
- [ ] Empty `ContentView` renders in a resizable window (min 700x500)
- [ ] App name is "WriteAssist" in the title bar
- [ ] `swift build` succeeds with no warnings
- [ ] SwiftLint config file (`.swiftlint.yml`) present at project root

### US-002: Implement the text editor view
**Description:** As a user, I want a text editor where I can type or paste text so that I have content to check.

**Acceptance Criteria:**
- [ ] `NSTextView` wrapped in a SwiftUI `NSViewRepresentable`
- [ ] Editor fills the main area of the window above the bottom panel
- [ ] Supports typing, pasting, selecting, copy, undo/redo
- [ ] Text content is bound to a shared view model (`@Observable` or `@ObservableObject`)
- [ ] Editor respects system light/dark mode automatically
- [ ] Placeholder text shown when editor is empty: "Type or paste your text here..."

### US-003: Implement debounced auto-check with NSSpellChecker
**Description:** As a user, I want my text automatically checked for spelling and grammar errors after I stop typing so that I get feedback without pressing a button.

**Acceptance Criteria:**
- [ ] Text changes trigger a check after ~1 second of idle (debounced)
- [ ] `NSSpellChecker.checkSpelling(of:startingAt:)` used for spelling detection
- [ ] `NSSpellChecker.checkGrammar(of:startingAt:)` used for grammar detection
- [ ] Detected issues stored in the view model as an array of issue objects (type, range, suggestions)
- [ ] Check runs on a background thread; results applied on main thread
- [ ] Previous check is cancelled if user resumes typing before it completes

### US-004: Highlight spelling and grammar errors in the editor
**Description:** As a user, I want spelling errors underlined in red and grammar errors underlined in blue so that I can visually identify issues.

**Acceptance Criteria:**
- [ ] Spelling errors display a red wavy/dotted underline on the affected text range
- [ ] Grammar errors display a blue wavy/dotted underline on the affected text range
- [ ] Underlines update after each auto-check completes
- [ ] Underlines are removed when the underlying text is edited
- [ ] Overlapping ranges handled gracefully (no crash or visual artifacts)

### US-005: Show suggestion popover on clicking highlighted text
**Description:** As a user, I want to click on a highlighted word to see correction suggestions so that I can fix errors.

**Acceptance Criteria:**
- [ ] Clicking on underlined text opens an `NSPopover` anchored to the clicked word
- [ ] Popover displays a list of suggested corrections (from `NSSpellChecker`)
- [ ] Each suggestion is clickable
- [ ] An "Ignore" button is present in the popover
- [ ] Popover dismisses when clicking outside of it
- [ ] If no suggestions are available, popover shows "No suggestions" with only the Ignore option

### US-006: Apply or ignore corrections
**Description:** As a user, I want to apply a suggestion with a single click or ignore the issue so that I can quickly fix or dismiss errors.

**Acceptance Criteria:**
- [ ] Clicking a suggestion replaces the highlighted text range with the selected correction
- [ ] Text view updates immediately after replacement
- [ ] The issue is removed from the issues list after applying a correction
- [ ] Auto-check re-triggers after applying a correction (respecting debounce)
- [ ] Clicking "Ignore" dismisses the popover and removes the underline for that issue
- [ ] Ignored issues are not re-flagged until the text at that location changes

### US-007: Implement collapsible bottom issues panel
**Description:** As a user, I want a bottom panel listing all detected issues so that I can see an overview and navigate to each one.

**Acceptance Criteria:**
- [ ] Bottom panel shows a scrollable list of all current issues
- [ ] Each row displays: issue type icon (spell/grammar), the flagged text, and a brief description
- [ ] Clicking a row scrolls the editor to and selects the relevant text range
- [ ] Panel shows issue count in its header (e.g., "Issues (5)")
- [ ] Panel is collapsible via a toggle button or disclosure triangle
- [ ] Panel defaults to expanded when issues exist, collapsed when none

### US-008: Display word and character count
**Description:** As a user, I want to see word and character counts so that I can track my writing length.

**Acceptance Criteria:**
- [ ] Word count and character count displayed in a toolbar or status bar area
- [ ] Counts update in real time as the user types
- [ ] Format: "X words | Y characters"
- [ ] Counts are accurate (whitespace-only input shows 0 words)

### US-009: App polish and light/dark mode support
**Description:** As a user, I want the app to look polished and adapt to my system appearance so that it feels native.

**Acceptance Criteria:**
- [ ] All UI elements (editor, panel, toolbar, popover) render correctly in light mode
- [ ] All UI elements render correctly in dark mode
- [ ] Switching system appearance updates the app without restart
- [ ] Window is resizable with sensible minimum size (700x500)
- [ ] App icon placeholder is set (SF Symbol or simple graphic)
- [ ] Menu bar includes standard Edit menu items (Copy, Paste, Select All, Undo, Redo)

## Functional Requirements

- FR-1: User can type or paste text into the editor
- FR-2: Application detects spelling errors in English text using `NSSpellChecker`
- FR-3: Application detects basic grammar issues using `NSSpellChecker`
- FR-4: Spelling errors are underlined in red
- FR-5: Grammar errors are underlined in blue
- FR-6: Text is auto-checked after ~1 second of typing idle
- FR-7: User can click highlighted text to view suggestions in an `NSPopover`
- FR-8: User can apply a correction with a single click
- FR-9: User can ignore a suggestion, removing the underline
- FR-10: Collapsible bottom panel lists all detected issues
- FR-11: Clicking an issue in the panel navigates to it in the editor
- FR-12: Word and character count displayed and updated in real time

## Non-Goals (Out of Scope for MVP)

- AI rewriting or paraphrasing
- Style, tone, or readability analysis
- Multi-language support
- Browser extensions or system-wide text checking
- User accounts or cloud sync
- Document saving, file import/export, or history
- Plagiarism detection
- Manual "Check" button (auto-check only for MVP)
- Custom dictionary or "add to dictionary" functionality

## Technical Considerations

- **Platform:** macOS 15 Sequoia only
- **Framework:** SwiftUI with `NSViewRepresentable` wrapping `NSTextView`
- **Spell/Grammar Engine:** `NSSpellChecker` (no external dependencies)
- **Project Structure:** Swift Package Manager (`Package.swift`), buildable via `swift build`
- **Architecture:** MVVM pattern — `@Observable` view model holds text, issues, and stats
- **Threading:** Spell/grammar checks dispatched off main thread; UI updates on main thread
- **Performance:** Check response under 2 seconds for ~1,000 words

## Success Metrics

- `swift build` compiles with zero errors and zero warnings
- `swiftlint` passes with zero violations
- Spelling detection accuracy >90% on common English misspellings
- Grammar issues detected for basic patterns (subject-verb agreement, missing articles)
- Check latency under 2 seconds for 1,000 words
- No crashes during normal typing, pasting, and correction workflows

## Open Questions

- Should "Ignore" persist only for the session, or should it survive across app launches (post-MVP)?
- Should the bottom panel support filtering by issue type (spelling vs grammar)?
- Is there a preferred app icon design or should a placeholder SF Symbol be used?
[/PRD]
