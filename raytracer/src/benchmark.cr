# Benchmark Raytracer - Original simple version for performance testing
#
# Build options:
#   shards build --release -Dpreview_mt --mcpu=native --mcmodel=kernel
#
# Run with:
#   CRYSTAL_WORKERS=16 ./bin/benchmark
#
# This is the original benchmark without any fancy features (no AA, no env vars)
# Use this for pure performance comparisons.
#
require "crimage"
require "./raytracer/common"

width = 500
height = 500

default_scene = DefaultScene.new
scene = default_scene.to_scene

t1 = Time.monotonic
ray_tracer = RayTracer.new
buffer = ray_tracer.render(scene, width, height)
t2 = Time.monotonic - t1

puts "Completed in #{(t2.total_milliseconds).round(3)} ms"

# Convert buffer to CrImage for PNG output
img = CrImage::RGBA.from_buffer(buffer, width, height)
CrImage::PNG.write("crystal-raytracer.png", img)
