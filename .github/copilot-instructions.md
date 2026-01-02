# PoseTrainer – App Overview

## Purpose
The main purpose of this app is to gamify drawing practice and provide fast feedback to some ground truth for any exercises where this is possible. The most basic feature is the ability to do timed pose/figure drawing from a reference image, and be able to overlay the reference and drawing to see how well you did afterwards.

## Current Features
- Timed drawing sessions with a reference image
- Overlay review of drawing and reference image with adjustable opacity
- Save paired reference + drawing sessions with minimal metadata (source URL, timestamp)
- e621 tag search (safe default) to pick reference images
- Google drive folder integration for selecting folders to sample reference images from.

## Tech Stack
The app should be cross-platform (Windows, iOS, Android, Web) and use Flutter for the UI. Focus is on Web first, as this is the most universal platform and easiest to deploy updates to. The tech stack should be fully wasm compatible to maximize performance on web. Rust and wgpu will be used to implement the drawing canvas and brush engine. This should be runnable as a standalone app so that the drawing experience can be tested independently of the rest of the app, and potentially re-used for other applications in the future.

## Next Steps
- Implement different kinds of exercises beyond timed pose drawing, such as line quality exercises, rotating forms, and form manipulation exercises. Form manipulation should involve intersecting, stacking, bending, and subtracting simple 3D shapes to create more complex forms. See:
[Minimalist Drawing Plan](https://youtu.be/HLzs_8kgaAY?si=p9eW2ufD4fhByL1t)
[Exercises Book](https://drive.google.com/file/d/1fCdZeT0cq2ZVQX9CePsI8qOW3nS9CRwb/view)