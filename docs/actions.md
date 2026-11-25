# Application actions

Select an app and click Actions or press ⌘K. The arrowless menu floats above the footer inside the launcher. It scales and fades from the Actions button on opening and reverses on closing, using the same timing as Get Info. Reduce Motion makes both transitions immediate. Use the arrow keys and Return to choose an action, or click it. Escape or a click elsewhere in the panel closes the menu.

- **Open** launches the selected app.
- **Show in Finder** reveals the app bundle.
- **Get Info** splits the results area evenly between the app list and details for the current selection. It shows the app icon and available Finder details, including location, dates, tags, comments, ownership, and access rules. Bundle details include version, build, identifier, executable, minimum macOS, and copyright when supplied by the app. Size counts regular file contents inside the bundle. Escape or the close button restores the full-width list. The split animates in both directions when Reduce Motion is off.
- **Quick Look** previews the app bundle using macOS Quick Look.
- **Share…** opens the macOS sharing picker for the app bundle.

The Actions feature owns menu selection and presentation. The launcher supplies the selected URL and its existing open and dismiss operations. See the [project instructions](../AGENTS.md#build-and-verify) for build and test commands. Verify keyboard navigation and system presentations in the running launcher.
