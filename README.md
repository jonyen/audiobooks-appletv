# BibleTV — ESV Bible for Apple TV

A SwiftUI Apple TV app that displays the Bible in the English Standard Version (ESV) and reads it aloud, chapter by chapter, using Crossway's official ESV audio (Hear the Word, read by David Cochran Heath).

## Features

- **Browse** all 66 books (Old and New Testament) and pick any chapter from a grid
- **Read** the full chapter text on screen in a large serif face with subtle verse-number markers
- **Listen** to the chapter's audio with play/pause and playback speed (0.75×–1.5×)
- **Auto-advance**: when a chapter's audio finishes, the app moves to the next chapter and keeps reading — listen through a whole book hands-free
- Recently played chapters are cached on-device so replays don't re-download

## Setup

1. **Get a free ESV API key.** Create an account at [api.esv.org](https://api.esv.org/), register an application, and copy your API key.
2. **Add the key to the app.** Open `BibleTV/Support/Secrets.swift` and paste your key:

   ```swift
   enum Secrets {
       static let esvAPIKey = "YOUR_KEY_HERE"
   }
   ```

   To keep your key from being committed back to git:

   ```sh
   git update-index --skip-worktree BibleTV/Support/Secrets.swift
   ```

3. **Build and run.** Open `BibleTV.xcodeproj` in Xcode 16 or later, select the *BibleTV* scheme and an Apple TV simulator (or your Apple TV), and run.

If you run the app without a key, it shows setup instructions instead of the library.

## Project layout

```
BibleTV/
├── BibleTVApp.swift            App entry point
├── Models/
│   └── BibleBook.swift         The 66 books with chapter counts
├── Services/
│   ├── ESVClient.swift         ESV API client (passage text + audio download/cache)
│   └── AudioPlayerModel.swift  AVPlayer wrapper (play/pause, rate, progress, finish events)
├── Views/
│   ├── BookListView.swift      OT/NT book list
│   ├── ChapterGridView.swift   Chapter picker grid
│   ├── ReaderView.swift        Chapter text + audio controls
│   └── SetupView.swift         Shown when no API key is configured
└── Support/
    └── Secrets.swift           Your ESV API key (placeholder committed)
```

## Licensing notes

This app uses the [ESV API](https://api.esv.org/), which is free for **non-commercial** use. Key conditions (see the API terms for the authoritative text):

- Display no more than 500 verses or half of a book at a time — a single chapter is always within this limit
- Cache no more than 500 verses — the app keeps only a handful of recent audio chapters on disk
- Display the ESV copyright attribution — shown in the reader's footer

Distribution on the App Store or any commercial use requires permission from [Crossway](https://www.crossway.org/permissions/).

Scripture quotations are from the ESV® Bible (The Holy Bible, English Standard Version®), © 2001 by Crossway, a publishing ministry of Good News Publishers. Used by permission. All rights reserved.
