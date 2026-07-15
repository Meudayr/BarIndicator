# BarIndicator WoW Addon

A lightweight, high-performance World of Warcraft addon that displays a visual indicator showing which page your main action bar is currently on (specifically highlighting pages 1 and 2). It also provides a secure feature to automatically hide your default main action bar when in combat, allowing you to clean up your UI while maintaining full awareness of your selected action bar page.

Works on **WoW Retail (Patch 12.0.5)**.

---

## Features
- **Clean Visual Indicator**: Displays a modern, compact dark tile indicating your current main action bar page.
- **Color Theme Signatures**: Customizable colors for Bar 1, Bar 2, and others.
- **Draggable & Custom Scale**: Easily reposition the frame anywhere on your screen by holding Shift and dragging. Scale can be set between `0.5` and `3.0`.
- **Integrated Options Menu**: A beautiful options panel built into the default WoW Options -> AddOns menu!
- **Visual Customizations**:
  - **Scale**: Change the size of the indicator.
  - **Font Size**: Change the scale of the number text.
  - **Background Opacity**: Set tile background transparency (`0.0` to `1.0`).
  - **Border Opacity**: Set tile border transparency (`0.0` to `1.0`).
- **Color Swatch Grids**: Instantly pick preset color combinations for Bar 1 and Bar 2 from a sleek row of swatches (Cyan, Gold, Red, Green, Blue, Purple, Orange, Magenta, Yellow, White).
- **Flexible Combat Visibility**: Configure the indicator to show/hide in-combat and out-of-combat independently.
- **Combat Autohiding**: Automatically hides Blizzard's default main action bar in combat using WoW's secure state drivers (doesn't cause Lua taints or combat errors).
- **Persistent Settings**: Saves all scale, coordinates, lock states, colors, and transparency preferences.

---

## Installation
1. Locate your World of Warcraft installation folder (e.g., `C:\Program Files\World of Warcraft\_retail_\`).
2. Navigate to `Interface\AddOns\`.
3. Copy the **`BarIndicator`** folder (the folder containing `BarIndicator.toc` and `BarIndicator.lua`) into the `AddOns` directory.
4. Launch (or restart) World of Warcraft, make sure **BarIndicator** is enabled in your AddOns menu, and log in.

---

## Usage

### In-Game Options Menu
- Type **`/bi config`** or **`/bi options`** in your chat window to open the settings category directly under WoW's Game Options menu.
- Alternatively, press `Esc` -> `Options` -> click the `AddOns` tab -> select `BarIndicator`.

### Repositioning the Indicator
By default, the indicator is unlocked and can be moved.
- Hold **`Shift` + Left Mouse Button** on the indicator and drag it to your desired location.
- Type `/bi lock` in chat or toggle the "Lock Frame Position" checkbox in the options menu to lock it in place.

### Slash Commands
You can configure the addon using `/barindicator` or `/bi`:
- `/bi config` - Open the Options config menu.
- `/bi lock` - Lock or unlock the indicator frame position.
- `/bi hide` - Toggle whether to hide the default main action bar in combat.
- `/bi scale <number>` - Scale the indicator frame (e.g., `/bi scale 1.2` makes it larger; range is `0.5` to `3.0`).
- `/bi reset` - Resets position, scale, colors, and settings back to default.
