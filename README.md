# FV-Reaper-Scripts
REAPER scripts by frioventus.


# FV TrackFlow 🌊
**The track template assistant for REAPER.**

![FV TrackFlow Preview](docs/preview.gif)

## The Problem vs. The Solution
**The Problem:** I used to work with massive project templates containing over 600 tracks. It created visual chaos, and a single project save file would easily exceed 200MB. Factoring in backups and autosaves, each project was consuming a minimum of 3GB of drive space. I decided to switch to Track Templates to fix this, but I quickly hit another wall: native REAPER templates completely forget your custom send routing and the specific folders they belong to when imported. Finally, just finding the exact track template you need takes too much time and completely breaks your creative flow.

**The Solution:** FV TrackFlow keeps your workflow lean and lightning-fast. With a powerful fuzzy search, you can effortlessly grab and insert multiple tracks at once. TrackFlow never forgets: it instantly restores your **custom send routing** and precisely places every track under its assigned parent track—automatically converting the target into a folder if it isn't one already.

---

## Features

### 🔍 Find & Insert Instantly
![Search and Insert Preview](docs/feature_search.gif)

Stop digging through folders. Use fuzzy search and tags to instantly find what you need. Select multiple tracks and insert them all at or simply drag and drop them directly into your project.

### 🔀 Routing & Folders
![Auto Routing Preview](docs/feature_routing.gif)

Inserted tracks automatically recreate your **custom send routing** (with exact dB levels) and snap right into their assigned parent folders without messing up your project structure.

### 💎 Minimalist & Contextual UI
![Minimalist UI Preview](docs/feature_minimalist.gif)

TrackFlow is designed with a strict minimalist philosophy to keep your workspace clutter-free. Action buttons and secondary options only reveal themselves contextually when you hover, select, or actually need them—ensuring nothing distracts you from your music.

### ⚙️ Build Your Database in Seconds
![Database Editor Preview](docs/feature_editor.gif)

Organize your track template folders on your drive exactly how you like them, then mirror that exact structure into TrackFlow with a single click using the **Scan** button in the Editor (`Ctrl+E`). 

From there, it's incredibly easy to organize your library: assign tags, configure send routing, and set target folders. Want to apply the same settings to multiple tracks? Just copy and paste your tags, sends, and target folders across other templates with a single click. As a bonus, TrackFlow automatically parses your `.RTrackTemplate` files to extract and display the exact VST/AU instrument loaded inside.


### 🎨 Match Your Workflow & Theme
![Theme Customizer Preview](docs/feature_themes.gif)

Your tools should feel like a native part of your workspace. TrackFlow is fully dockable and highly responsive, meaning you can use it as a vertical sidebar, a horizontal panel, or a compact floating square. Open the Theme Customizer (`Ctrl+T`) to choose from carefully crafted built-in presets (like Studio Dark, Nordic, or Dracula), or manually tweak every single color, padding, and border radius to perfectly match your custom REAPER theme.

---

## 🚀 Installation (via ReaPack)

1. Ensure you have [ReaPack](https://reapack.com/) installed in REAPER.
2. Go to **Extensions > ReaPack > Import repositories**.
3. Paste the following repository link:
   ```text
   https://raw.githubusercontent.com/frioventus/FV-Reaper-Scripts/main/index.xml
4. Search for FV TrackFlow in the ReaPack browser, install, and apply.
