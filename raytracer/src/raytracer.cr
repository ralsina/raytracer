# Raytracer - Full-featured version with AA and configurable resolution
#
# For pure benchmarking, use benchmark.cr instead
#
# Build options:
#   shards build --release -Dpreview_mt --mcpu=native --mcmodel=kernel
#
# Run with:
#   CRYSTAL_WORKERS=16 ./bin/raytracer
#
# With custom resolution:
#   CRYSTAL_WORKERS=16 SIZE=800 ./bin/raytracer
#
# With antialiasing (adaptive by default, faster):
#   CRYSTAL_WORKERS=16 AA_SAMPLES=4 ./bin/raytracer
#   CRYSTAL_WORKERS=16 AA_SAMPLES=32 SIZE=1000 ./bin/raytracer
#
# With full non-adaptive antialiasing (prettier but slower):
#   CRYSTAL_WORKERS=16 AA_SAMPLES=4 ADAPTIVE_AA=0 ./bin/raytracer
#
# Environment variables:
#   SIZE - Image size (default 500, square images)
#   AA_SAMPLES - Antialiasing samples (default 1, use 4-32 for AA)
#   ADAPTIVE_AA - Adaptive mode (default 1, set 0 for full sampling)
#   MAX_DEPTH - Maximum reflection bounces (default 5)
#
require "crimage"
require "./raytracer/common"

size = (ENV["SIZE"]? || "500").to_i
width = size
height = size

samples = (ENV["AA_SAMPLES"]? || "1").to_i

default_scene = DefaultScene.new
scene = default_scene.to_scene

t1 = Time.monotonic
ray_tracer = RayTracer.new
buffer = ray_tracer.render(scene, width, height, samples)
t2 = Time.monotonic - t1

puts "Completed in #{(t2.total_milliseconds).round(3)} ms"

# Convert buffer to CrImage for PNG output
img = CrImage::RGBA.from_buffer(buffer, width, height)
CrImage::PNG.write("crystal-raytracer.png", img)
