# PoseTrainer – App Overview

## Purpose
The main purpose of this app is to gamify drawing practice and provide fast feedback to some ground truth for any exercises where this is possible. The most basic feature is the ability to do timed pose/figure drawing from a reference image, and be able to overlay the reference and drawing to see how well you did afterwards.

## Current Features
- Timed drawing sessions with a reference image
- Overlay review of drawing and reference image with adjustable opacity
- Save paired reference + drawing sessions with minimal metadata (source URL, timestamp)
- e621 tag search (safe default) to pick reference images
- Google drive folder integration for selecting folders to sample reference images from. (There are some double sign-in flow issues on web, and it is not fully tested on desktop or mobile).
- Basic (limited) pure flutter based brush engine / canvas. The current implementation has issues with periodic dab opacity artifacts and latency. It also cannot handle more than one stroke color on the canvas, or more complicated pressure based opacity control for brushes.

## Tech Stack
The app should be cross-platform (Windows, iOS, Android, Web) and use Flutter for the UI. Focus is on Web first, as this is the most universal platform and easiest to deploy updates to. The tech stack should be fully wasm compatible to maximize performance on web. Rust and wgpu will be used to implement the drawing canvas and brush engine. This should be runnable as a standalone app so that the drawing experience can be tested independently of the rest of the app, and potentially re-used for other applications in the future.

### Current Implementation
The current implementation is pure Flutter code, including the drawing canvas and brush engine.

# PoseTrainer – Copilot Instructions

## Requrested Response Style
You are a senior pair‑programmer and design coach. Respond with explanations, plans, pseudocode, and small single‑file snippets only. Do not implement multi‑file changes or full features unless the user explicitly approves. Prioritize readability, explicit contracts, and tests. Ask clarifying questions before large changes.
