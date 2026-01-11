# Animated Raytracer Design

## Overview

A separate `animated` binary that renders the raytraced scene at 800x600 in real-time to an X11 window using stumpy_x11. The scene features animated spheres (bouncing), animated lights (color cycling/rotating), and a slowly orbiting camera. Current FPS is displayed in the window title to show off performance.

Target is 60+ FPS at 800x600 (up from 7ms at 500x500, so ~13-16ms per frame expected due to 2.56x more pixels).

## Architecture

**Two binaries:**
- `src/raytracer.cr` - Existing benchmark (unchanged)
- `src/animated.cr` - New animated version

**Shared code:**
- Move common structs/classes to `src/raytracer/common.cr`
- Both binaries require the shared raytracer engine
- Animated version adds time parameter to scene construction

**Animation loop:**
1. Get current time (elapsed seconds since start)
2. Build animated scene based on time
3. Render to RGBA buffer
4. Push buffer to X11 window via stumpy_x11
5. Update window title with FPS
6. Repeat until window closed

**FPS calculation:**
- Track frames rendered and time elapsed
- Update title every ~500ms to avoid flicker
- Show "FPS: XX" in window title

## Data Structures

**Animated scene parameter:**
```crystal
class AnimatedScene < DefaultScene
  def initialize(time : Float64)
    # Calculate positions based on time
    # Override things, lights, camera
  end
end
```

**Animation formulas:**
- **Sphere bouncing**: `y = base_y + abs(sin(time * speed)) * amplitude`
- **Light color cycling**: HSV to RGB conversion, hue = `time * 0.1`
- **Light rotation**: Orbit around origin, `x = cos(time) * radius`, `z = sin(time) * radius`
- **Camera orbit**: `x = cos(time * 0.05) * distance`, `z = sin(time * 0.05) * distance`, always looking at origin

**FPS tracker:**
```crystal
struct FPSCounter
  property frames : Int32
  property last_update : Time::Mono
  property fps : Float64

  def update : Bool
    # Increment frame counter
    # Return true if 500ms elapsed (update title)
  end
end
```

## Implementation Flow

**Main loop in `src/animated.cr`:**
```crystal
require "stumpy_x11"
require "./raytracer/common"

# Initialize X11 display
display = StumpyX11::Display.new
window = display.create_window(800, 600)
window.title = "Animated Raytracer - FPS: --"

start_time = Time.monotonic
fps_counter = FPSCounter.new

while display.window_open?
  elapsed = (Time.monotonic - start_time).total_seconds

  # Render scene at this time
  scene = AnimatedScene.new(elapsed)
  buffer = ray_tracer.render(scene, 800, 600)

  # Convert buffer to X11 image and display
  display.put_image(window, buffer)

  # Update FPS in title if needed
  if fps_counter.update
    window.title = "Animated Raytracer - FPS: #{fps_counter.fps.to_i}"
  end
end
```

**File structure:**
```
src/
  raytracer.cr          # Original benchmark (unchanged)
  animated.cr           # New animated binary
  raytracer/
    common.cr           # Shared structs, classes, Scene, RayTracer
```

## Error Handling & Edge Cases

**X11 connection failures:**
- If X11 display not available → graceful error message "Cannot connect to X11 display. Are you running in a graphical environment?"
- If stumpy_x11 not installed → clear error during build, shard dependency handles this

**Window close handling:**
- stumpy_x11 provides event checking for window close
- Clean shutdown on close, no resource leaks

**Performance degradation:**
- If FPS drops below 30, maybe warn or log but keep running
- No hard FPS requirement - just show what it can do

**Time overflow:**
- After many hours, `elapsed` could get large
- Use `time % (2 * Math::PI)` for trig functions to keep values bounded
- Or just let it grow - Float64 has plenty of precision for hours of runtime

**Coordinate safety:**
- Clamp all color values to 0-1 range (already done)
- Normalize vectors (already done in raytracer)

## Testing Strategy

**Manual testing checklist:**
1. Window opens at 800x600
2. Spheres bounce smoothly at different rates
3. Light colors cycle visibly
4. Camera slowly orbits the scene
5. FPS counter updates in title bar
6. Window closes cleanly

**Performance validation:**
- Should see 40-60+ FPS on modern hardware
- Compare to benchmark: 7ms @ 500x500 → expect ~13-18ms @ 800x600 (2.56x pixels)

**Code testing:**
- No automated tests needed (visual demo)
- Verify it compiles without warnings
- Check both binaries still work (original raytracer and animated)
