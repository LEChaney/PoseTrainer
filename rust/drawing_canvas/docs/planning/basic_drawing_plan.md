# Basic Functionality
The basic drawing capabilities of the drawing canvas should include the following features:
- Basic round brush shape
- Brush Parameters:
  - Size (in pixels)
  - Flow/Per-dab-opacity (0-100%)
  - Hardness (0-100%)
  - Spacing (in pixels)
  - Color
- Pressure sensitivity for controlling stroke width and per-dab opacity (flow).
- Support for using pressure (and later other inputs such as tilt, roll, and azimuth) to be setup to control different brush parameters (the default brush should use pressure to control flow only, but it should be easy to swap this around to control different parameters).

# Latency & Battery Considerations
To minimize latency and conserve battery, the drawing canvas should request a redraw only when it receives new input events from the stylus or mouse. If there is a currently in-flight frame being rendered, but no next frame event scheduled, we should request a new frame to be queued up as soon as the current frame is done rendering. Any new input events received while a frame is in-flight should be coalesced into the next frame to be rendered.

# Rendering Approach
When the renderer kicks off a new frame, it should:
1. Process all input events received since the last frame.
2. For each input event, calculate the brush dabs (might be more, or less, than input events due to spacing parameter) needed based on the brush parameters and input data (position, pressure, etc).
3. Render the calculated brush dabs using instanced rendering for efficiency (all dabs for the frame should be rendered in a single draw call) using linear space colors for blending.
4. Resolve the final linear space framebuffer to the current display's color space for display.

# Interop Considerations
Since this rust drawing canvas is meant to be embedded into other applications that will control UI and layout, the drawing canvas code should avoid implementing any of its own UI code. However, windowing code will still mostly be handled inside this app since we can use html canvas and webview on mobile to embed the drawing canvas. This way all the UI code can be handled by the embedding application, and this drawing canvas can focus solely on rendering and input handling. Since we won't have UI in the rust app, we need to ensure that all configuration of brush parameters and other settings can be done via a simple API that the embedding application can call into. This API should be well documented and easy to use from other languages and frameworks (Flutter and Javascript). For testing functionality when running the canvas standalone, we can implement a simple HTML based UI that allows tweaking brush parameters and testing drawing functionality. This should be kept separate from the core drawing canvas code so that it is not included when the canvas is embedded into other applications.