# Animated Raytracer - Real-time X11 display
#
# Build options:
#   shards build --release -Dpreview_mt --mcpu=native --mcmodel=kernel
#
# Run with:
#   CRYSTAL_WORKERS=16 ./bin/animated
#
# With custom resolution:
#   CRYSTAL_WORKERS=16 SIZE=800 ./bin/animated
#
# With antialiasing (adaptive by default, faster):
#   CRYSTAL_WORKERS=16 AA_SAMPLES=4 ./bin/animated
#
# With full non-adaptive antialiasing (prettier but slower):
#   CRYSTAL_WORKERS=16 AA_SAMPLES=4 ADAPTIVE_AA=0 ./bin/animated
#
# With custom reflection depth (default 5):
#   CRYSTAL_WORKERS=16 MAX_DEPTH=10 ./bin/animated
#
# With custom background color (hex):
#   CRYSTAL_WORKERS=16 BACKGROUND_COLOR=1a1a2e ./bin/animated
#
# Requires SDL2 development libraries:
#   Ubuntu/Debian: sudo apt install libsdl2-dev
#   Arch: sudo pacman -S sdl2
#   Fedora: sudo dnf install SDL2-devel
#
require "sdl"
require "./raytracer/common"

WIDTH  = (ENV["SIZE"]? || "500").to_i
HEIGHT = WIDTH

# Animated scene with time-based animations
class AnimatedScene < DefaultScene
  def initialize(time : Float64)
    super()

    # Animate spheres - bounce up and down at different rates
    @things = [
      Plane.new(Vector.new(0.0_f64, 1.0_f64, 0.0_f64), 0.0_f64, SURFACE_CHECKERBOARD),
      # Main sphere bounces slowly
      Sphere.new(
        Vector.new(0.0_f64, 1.0_f64 + Math.sin(time * 2.0).abs.to_f64 * 0.5_f64, -0.25_f64),
        1.0_f64,
        SURFACE_SHINY
      ),
      # Small sphere bounces faster
      Sphere.new(
        Vector.new(-1.0_f64, 0.5_f64 + Math.sin(time * 3.5 + 1.0).abs.to_f64 * 0.8_f64, 1.5_f64),
        0.5_f64,
        SURFACE_SHINY
      ),
      # Add a third sphere that bounces at medium speed on the other side (matte red, not shiny)
      Sphere.new(
        Vector.new(1.5_f64, 0.6_f64 + Math.sin(time * 2.8 + 2.0).abs.to_f64 * 0.7_f64, 0.5_f64),
        0.6_f64,
        MatteSurface.new(Color.new(0.9_f64, 0.1_f64, 0.1_f64))
      ),
    ] of Thing

    # Animate lights - cycle colors and orbit positions
    hue = (time * 20.0) % 360.0
    orbit_radius = 2.5_f64

    @lights = [
      # Light 1 - orbits and cycles color
      Light.new(
        Vector.new(
          Math.cos(time * 0.5).to_f64 * orbit_radius,
          2.5_f64,
          Math.sin(time * 0.5).to_f64 * orbit_radius
        ),
        Color.from_hsv(hue.to_f64, 0.8_f64, 0.6_f64)
      ),
      # Light 2 - orbits at different speed, offset color
      Light.new(
        Vector.new(
          Math.cos(time * 0.3 + 2.0).to_f64 * orbit_radius * 0.8_f64,
          2.5_f64,
          Math.sin(time * 0.3 + 2.0).to_f64 * orbit_radius * 0.8_f64
        ),
        Color.from_hsv((hue + 120.0).to_f64, 0.8_f64, 0.6_f64)
      ),
      # Light 3 - third orbit, different color
      Light.new(
        Vector.new(
          Math.cos(time * 0.7 + 4.0).to_f64 * orbit_radius * 0.6_f64,
          3.0_f64,
          Math.sin(time * 0.7 + 4.0).to_f64 * orbit_radius * 0.6_f64
        ),
        Color.from_hsv((hue + 240.0).to_f64, 0.8_f64, 0.6_f64)
      ),
      # Light 4 - overhead, static position but color cycles
      Light.new(
        Vector.new(0.0_f64, 3.5_f64, 0.0_f64),
        Color.from_hsv((hue + 60.0).to_f64, 0.5_f64, 0.4_f64)
      ),
    ]

    # Animate camera - slowly orbits the scene
    cam_distance = 5.0_f64
    cam_x = Math.cos(time * 0.1).to_f64 * cam_distance
    cam_z = Math.sin(time * 0.1).to_f64 * cam_distance
    @camera = Camera.new(
      Vector.new(cam_x, 2.5_f64, cam_z),
      Vector.new(0.0_f64, 0.5_f64, 0.0_f64)
    )
  end
end

# Initialize SDL
begin
  SDL.init(SDL::Init::VIDEO)
rescue ex
  STDERR.puts "Error: Cannot initialize SDL."
  STDERR.puts "Make sure SDL2 is installed:"
  STDERR.puts "  Ubuntu/Debian: sudo apt install libsdl2-dev"
  STDERR.puts "  Arch: sudo pacman -S sdl2"
  STDERR.puts "  Fedora: sudo dnf install SDL2-devel"
  STDERR.puts "Error details: #{ex.message}"
  exit 1
end

# Create window
window = SDL::Window.new("Animated Raytracer", WIDTH, HEIGHT)
renderer = SDL::Renderer.new(window)

# Create texture for rendering
texture = SDL::Texture.new(renderer, WIDTH, HEIGHT)

# FPS tracking
start_time = Time.monotonic
ray_tracer = RayTracer.new
frame_count = 0
last_fps_update = start_time

# Read settings for display
samples = (ENV["AA_SAMPLES"]? || "1").to_i
adaptive = (ENV["ADAPTIVE_AA"]? || "1").to_i != 0
max_depth = (ENV["MAX_DEPTH"]? || "5").to_i
workers = (ENV["CRYSTAL_WORKERS"]? || "8").to_i
bg_color = ENV["BACKGROUND_COLOR"]? || "000000"

puts "Animated Raytracer"
puts "Rendering #{WIDTH}x#{HEIGHT} in real-time"
puts ""
puts "Settings:"
puts "  Resolution: #{WIDTH}x#{HEIGHT}"
puts "  Workers: #{workers}"
puts "  AA Samples: #{samples}"
puts "  Adaptive AA: #{adaptive ? "enabled" : "disabled"}"
puts "  Max Depth: #{max_depth}"
puts "  Background Color: ##{bg_color}"
puts ""
puts "Press ESC or close window to exit"
puts ""

running = true
while running
  frame_start = Time.monotonic
  elapsed = (Time.monotonic - start_time).total_seconds

  # Handle SDL events
  while event = SDL::Event.poll
    case event
    when SDL::Event::Quit
      running = false
    when SDL::Event::Keyboard
      if event.sym == 27 # SDLK_ESCAPE
        running = false
      end
    end
  end

  break unless running

  # Render scene at this time
  animated_scene = AnimatedScene.new(elapsed)
  scene = animated_scene.to_scene
  buffer = ray_tracer.render(scene, WIDTH, HEIGHT, samples)

  # Lock texture and update pixel data
  texture.lock do |pixels, _|
    # Convert RGBA buffer to RGB (SDL stores as UInt32 per pixel)
    buffer_idx = 0
    (WIDTH * HEIGHT).times do |i|
      r = buffer[buffer_idx]
      g = buffer[buffer_idx + 1]
      b = buffer[buffer_idx + 2]
      # Skip alpha (buffer_idx + 3)
      buffer_idx += 4

      # Pack RGB into UInt32 (try ARGB order)
      pixels[i] = (r.to_u32 << 24) | (g.to_u32 << 16) | (b.to_u32 << 8) | 0xFF_u32
    end
  end

  # Render texture to screen
  renderer.copy(texture)
  renderer.present

  # Update FPS counter every 500ms
  now = Time.monotonic
  if (now - last_fps_update).total_milliseconds >= 500
    total_elapsed = (now - start_time).total_seconds
    fps = total_elapsed > 0 ? frame_count / total_elapsed : 0.0
    render_time = (now - frame_start).total_milliseconds

    puts "FPS: #{fps.round(1)} | Frame time: #{render_time.round(1)}ms"
    window.title = "Animated Raytracer - #{fps.round(1)} FPS (#{render_time.round(1)}ms/frame)"
    last_fps_update = now
  end

  frame_count += 1
end

puts "Animation closed after #{frame_count} frames."
