---
title: "Surface add-write failures in the Add sheet"
status: open
priority: high
date: 2026-06-19
source: "Scout#40 review follow-up"
---

# Surface add-write failures in the Add sheet

The add path currently swallows write errors. Show them inline on the sheet,
the way the resolve path already surfaces errors on the card.

```swift
try await store.addItem(title: title, priority: priority, body: body, optional: optional)
```
