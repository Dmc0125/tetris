# Tetris

A learning project that implements Tetris in Odin, with a WebAssembly/web version and an older SDL-based desktop prototype.

## About

This repository contains a Tetris project written primarily in [Odin](https://odin-lang.org/).

The main implementation lives under `web/` and runs in the browser by compiling the game to WebAssembly. A small Go server serves the HTML and static assets, while a JavaScript bridge connects browser APIs (canvas, input, timing, fonts) to the Odin game code.

There is also a separate `desktop/` directory containing an SDL2-based desktop version/prototype.

## Features

### Web version
- Browser-based Tetris game rendered on an HTML canvas
- Odin game code compiled to WebAssembly
- Main menu with:
  - `Tetris classic`
  - `Coming soon` placeholder
- Singleplayer gameplay with:
  - 10x20 board
  - next-piece preview
  - score display
  - timer display
  - pause/resume flow
  - countdown before starting
  - game over state
  - ghost/projection piece
- Responsive UI layout for smaller and larger window sizes
- Keyboard input:
  - `Arrow Up` rotate
  - `Arrow Left` move left
  - `Arrow Right` move right
  - `Arrow Down` speed up drop
- Mouse input for menu/action buttons

### Codebase
- Custom UI/layout system in Odin
- Platform abstraction for wasm and non-wasm builds
- Tests for:
  - UI container layout
  - singleplayer 7-bag queue behavior

## Tech Stack

- **Odin** — game logic, UI system, platform bindings
- **WebAssembly** — browser target for the main game
- **JavaScript** — canvas rendering, input/event bridge, wasm host runtime
- **Go** — simple local web server
- **HTML/CSS** — page shell for the web version
- **SDL2 / SDL2_ttf** — used by the desktop prototype in `desktop/`

## Getting Started

## Prerequisites

For the web version:
- [Odin](https://odin-lang.org/)
- Go
- A browser

For the desktop prototype:
- Odin
- SDL2
- SDL2_ttf

## Web version

The main playable implementation is the web version under `web/`.

### Build the WebAssembly game

From `web/`:

```sh
./build.sh
```

This runs:

```sh
odin build ./game -out:./static/game.wasm -target:js_wasm32 -no-entry-point
```

### Run the web server

From `web/server/`:

```sh
go run .
```

The server listens on:

```text
http://localhost:8080
```

Open that URL in your browser.

### Static assets expected by the web app

The web app expects these files under `web/static/`:

- `game.wasm`
- `sprites.png`
- `editundo.ttf`
- `odin.js`

`odin.js` is included in the repo. `game.wasm` is produced by the build script.

## Desktop prototype

There is also a desktop implementation in:

```text
desktop/src/main.odin
```

It uses SDL2 and SDL2_ttf directly. No build script is included in the repository, so build/run details depend on your local Odin + SDL setup.

## Environment Variables

No `.env` file or environment variables are defined in the source.

## Usage

## Controls

### In the menu
- Click **Tetris classic** to start singleplayer

### In game
- `Arrow Up` — rotate piece
- `Arrow Left` — move left
- `Arrow Right` — move right
- `Arrow Down` — increase fall speed while held
- Click **Pause** / **Resume** / **Play again** button depending on state

## Game flow

- Start from the menu
- Enter singleplayer
- Click **Start**
- Wait for the countdown
- Play until game over
- Click **Play again** to restart

## Running tests

The repository includes Odin test files under:

- `web/game/tests/ui.odin`
- `web/game/tests/singleplayer.odin`

No test command is provided in the repo, but these files cover:
- UI layout sizing/positioning
- singleplayer queue correctness

## Notes

This project was intended for learning purposes, and the structure reflects that: it includes a custom UI system, platform abstraction, a wasm host bridge, and an additional desktop prototype alongside the browser version.
