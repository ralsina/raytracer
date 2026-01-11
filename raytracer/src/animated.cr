# Animated Raytracer - Outputs PNG frames
#
# Build options:
#   shards build --release -Dpreview_mt --mcpu=native --mcmodel=kernel
#
# Run with:
#   CRYSTAL_WORKERS=16 ./bin/animated
#
# This will render frames continuously and save them as frame_XXXX.png
# You can view them with:
#   - feh frame_*.png (image viewer)
#   - ffmpeg -framerate 30 -i frame_%04d.png -c:v libx264 -pix_fmt yuv420p output.mp4
#
require "crimage"
require "./raytracer/common"

WIDTH          = 800
HEIGHT         = 600
FPS            =  30
FRAME_DURATION = 1.0 / FPS

# Animated scene with time-based animations
class AnimatedScene < DefaultScene
  def initialize(time : Float64)
    super()

    # Animate spheres - bounce up and down at different rates
    @things = [
      Plane.new(Vector.new(0.0_f32, 1.0_f32, 0.0_f32), 0.0_f32, SURFACE_CHECKERBOARD),
      # Main sphere bounces slowly
      Sphere.new(
        Vector.new(0.0_f32, 1.0_f32 + Math.sin(time * 2.0).abs.to_f32 * 0.5_f32, -0.25_f32),
        1.0_f32,
        SURFACE_SHINY
      ),
      # Small sphere bounces faster
      Sphere.new(
        Vector.new(-1.0_f32, 0.5_f32 + Math.sin(time * 3.5 + 1.0).abs.to_f32 * 0.8_f32, 1.5_f32),
        0.5_f32,
        SURFACE_SHINY
      ),
      # Add a third sphere that bounces at medium speed on the other side
      Sphere.new(
        Vector.new(1.5_f32, 0.6_f32 + Math.sin(time * 2.8 + 2.0).abs.to_f32 * 0.7_f32, 0.5_f32),
        0.6_f32,
        SURFACE_SHINY
      ),
    ] of Thing

    # Animate lights - cycle colors and orbit positions
    hue = (time * 20.0) % 360.0
    orbit_radius = 2.5_f32

    @lights = [
      # Light 1 - orbits and cycles color
      Light.new(
        Vector.new(
          Math.cos(time * 0.5).to_f32 * orbit_radius,
          2.5_f32,
          Math.sin(time * 0.5).to_f32 * orbit_radius
        ),
        Color.from_hsv(hue.to_f32, 0.8_f32, 0.6_f32)
      ),
      # Light 2 - orbits at different speed, offset color
      Light.new(
        Vector.new(
          Math.cos(time * 0.3 + 2.0).to_f32 * orbit_radius * 0.8_f32,
          2.5_f32,
          Math.sin(time * 0.3 + 2.0).to_f32 * orbit_radius * 0.8_f32
        ),
        Color.from_hsv((hue + 120.0).to_f32, 0.8_f32, 0.6_f32)
      ),
      # Light 3 - third orbit, different color
      Light.new(
        Vector.new(
          Math.cos(time * 0.7 + 4.0).to_f32 * orbit_radius * 0.6_f32,
          3.0_f32,
          Math.sin(time * 0.7 + 4.0).to_f32 * orbit_radius * 0.6_f32
        ),
        Color.from_hsv((hue + 240.0).to_f32, 0.8_f32, 0.6_f32)
      ),
      # Light 4 - overhead, static position but color cycles
      Light.new(
        Vector.new(0.0_f32, 3.5_f32, 0.0_f32),
        Color.from_hsv((hue + 60.0).to_f32, 0.5_f32, 0.4_f32)
      ),
    ]

    # Animate camera - slowly orbits the scene
    cam_distance = 5.0_f32
    cam_x = Math.cos(time * 0.1).to_f32 * cam_distance
    cam_z = Math.sin(time * 0.1).to_f32 * cam_distance
    @camera = Camera.new(
      Vector.new(cam_x, 2.5_f32, cam_z),
      Vector.new(0.0_f32, 0.5_f32, 0.0_f32)
    )
  end
end

# Main animation loop
puts "Animated Raytracer"
puts "Rendering #{WIDTH}x#{HEIGHT} at #{FPS} FPS"
puts "Press Ctrl+C to stop"
puts ""

start_time = Time.monotonic
ray_tracer = RayTracer.new
frame_count = 0

# Create output directory
Dir.mkdir_p("frames")

loop do
  frame_start = Time.monotonic
  elapsed = (Time.monotonic - start_time).total_seconds

  # Render scene at this time
  animated_scene = AnimatedScene.new(elapsed)
  scene = animated_scene.to_scene
  buffer = ray_tracer.render(scene, WIDTH, HEIGHT)

  # Save frame
  frame_filename = "frames/frame_%04d.png" % frame_count
  img = CrImage::RGBA.from_buffer(buffer, WIDTH, HEIGHT)
  CrImage::PNG.write(frame_filename, img)

  render_time = (Time.monotonic - frame_start).total_milliseconds
  fps_actual = render_time > 0 ? 1000.0 / render_time : 0.0

  puts "Frame #{frame_count}: #{render_time.round(1)}ms (#{fps_actual.round(1)} FPS) - #{frame_filename}"

  frame_count += 1

  # Maintain target FPS
  sleep_time = FRAME_DURATION - (Time.monotonic - frame_start).total_seconds
  sleep(sleep_time.seconds) if sleep_time > 0
end
