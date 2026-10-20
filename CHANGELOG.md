# Changelog

## 1.1 — in progress

### Added
- **Clipboard history.** Press **⌥⌘V** anywhere, or choose Clipboard History… in the menu
  bar, to see what you've copied. Recent copies are grouped by day, each with the icon of the
  app it came from and a full preview.
  - **Paste (↵)** pastes an entry into the app you were in. **Copy (⌘C)** only puts it back
    on the clipboard.
  - **Save as Prompt (⌘S)** turns it into a Prompt Bank entry.
  - **Delete (⌘⌫)** removes it from the history.
- **Private by default.** History keeps text only, up to the last 200 copies, saved where
  only you can read it. It never records passwords that password managers mark as concealed,
  or Shorthand's own snippet pastes. Turn it off with Record Clipboard History in the menu
  bar, or clear it with Clear Clipboard History.

## 1.0 — 20 Oct 2026

The first release: a menu-bar text expander for macOS, in the spirit of TextExpander.

### Snippets
- **Type an abbreviation, get the text.** Type `;sig` anywhere and it's replaced with your
  sign-off, in any app. It expands as soon as the last character is typed.
- **Your clipboard is put back.** Snippets are pasted, then whatever you had copied returns.
  Clipboard managers are told to skip the temporary copy.
- **Snippets editor** with search, an enabled toggle per snippet, and a warning when two
  snippets share an abbreviation. Snippets are saved as JSON in
  `~/Library/Application Support/Shorthand/`.

### Templates
- **Filled in automatically:** `{date}`, `{time}`, `{isodate}`, `{clipboard}`, and
  `{cursor}` for where the caret ends up.
- **Variables:** save values once, like `{company}` → "Acme Pty Ltd", and use them in any
  snippet. Edit them with the `{}` Variables button in the editor.
- **Asked for when inserting:** any other `{Name}` opens a small form. There are also
  multi-line fields (`{fill:Notes:multi}`), menus (`{choice:Tone:friendly|formal}`) and
  sections you can leave out (`{optional:PS}…{/optional}`). Fields with the same name are
  filled once.
- **Code is left alone:** `${x}`, `{ return x }` and `{a.b}` stay exactly as typed.
- An **Add Placeholder** menu in the editor lists all of these, and each snippet shows what it
  will ask for.

### Prompt Bank
- **Text you reuse without a shortcut.** A snippet with no abbreviation lives in the Prompt
  Bank.
- **Type `;;` anywhere** to open a Raycast-style launcher with search, a preview with the
  placeholders highlighted, Insert (↵), Copy (⌘C) and Close (esc). It lists Prompt Bank
  entries first, then your shortcut snippets.
- The **Prompt Bank submenu** in the menu bar inserts a prompt with one click.

### App
- Lives in the menu bar, with Pause Expansion and Open at Login.
- Asks for Accessibility access on first launch, links to the right Settings pane, and notes
  when another app's Secure Input is blocking expansion.
- Doesn't expand inside its own editor and forms.

### Known limits
- Not notarized yet. Until it's signed with a Developer ID certificate, other Macs show a
  warning the first time it's opened (see the README).
- Snippets are plain text; rich text isn't supported.
