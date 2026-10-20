# DevScrapToolbox — specification

**Tagline:** An offline toolbox of everyday developer converters like JSON, [removed], JWT, hashes and timestamps, fed from your clipboard.

**Category:** Developer & Network

**Inspired by (paid):** DevUtils ($9 one-time)

**Frameworks:** SwiftUI, AppKit, CryptoKit, Foundation, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: DevUtils is a popular offline toolbox for developers sold for around 9 dollars, praised on Hacker News and Product Hunt as a fast replacement for scattered web based formatters, with clipboard detection that opens the right tool automatically. Our free clean-room version covers the most used tools with zero network use.

Feature set: A sidebar lists tools. JSON formatter and minifier with validation and error position. [removed] encode and decode. URL encode and decode. JWT decoder that shows header and payload with expiry as a readable date, without verifying signatures. Hash generator for MD5, SHA1, SHA256 and SHA512 using text or a dropped file. Unix timestamp converter in both directions with local and UTC output. UUID generator in bulk. Text case converter for camel, snake, kebab and upper. Each tool has an input pane and an output pane with a copy button. A smart paste action reads the clipboard, guesses the type, and opens the right tool with the content filled in.

UI spec: A window app with a NavigationSplitView, sidebar on the left with tool names and symbols, and the tool view on the right with two text editors stacked or side by side. A toolbar button labeled Paste and Detect, a swap button, and a clear button. A menu bar item opens the window from anywhere through a global hotkey. Settings has the hotkey, a font size choice, a toggle for auto detecting on activation, and launch at login. Empty states show a hint line describing what to paste. Errors display below the input in red with the line and column.

Technical approach: JSON uses JSONSerialization with the prettyPrinted and sortedKeys options and fragments allowed, and error positions are taken from the NSDebugDescription and the character index in the userInfo. [removed] and URL encoding use Foundation. JWT decoding splits on dots, pads and decodes base64url, then pretty prints JSON and converts exp, iat and nbf claims with a date formatter. Hashes use CryptoKit Insecure.MD5, Insecure.SHA1 and SHA256 or SHA512, reading files in chunks with a FileHandle and incremental hasher. Timestamps use Date and ISO8601DateFormatter, detecting seconds versus milliseconds by magnitude. Clipboard detection uses NSPasteboard string for content and simple heuristics: leading brace or bracket means JSON, three dot separated base64url segments means JWT, ten or thirteen digits means timestamp, percent sequences mean URL encoding. The hotkey uses Carbon RegisterEventHotKey. Preferences use AppStorage and launch at login uses SMAppService. No permissions are needed.

Edge cases and error handling: Invalid input in any tool shows an error and leaves the output empty rather than a crash. Very large JSON of several megabytes is processed off the main thread with a progress indicator. Binary or non UTF-8 [removed] output shows a hex preview and a save to file button. Malformed JWTs report which segment failed. Detect and warn that decoding a JWT does not verify it. About 650 lines.
