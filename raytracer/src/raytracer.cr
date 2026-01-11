# Raytracer - Ported from Ruby to Crystal
#
# Build options:
#   shards build --release -Dpreview_mt --mcpu=native --mcmodel=kernel
#
# Run with:
#   CRYSTAL_WORKERS=16 ./bin/raytracer
#
# With antialiasing:
#   CRYSTAL_WORKERS=16 AA_SAMPLES=4 ./bin/raytracer
#
# Performance: <7ms for 500x500 image with 16 workers
# Comparison:
#   Ruby original: ~550ms
#   This Crystal version: ~7ms (~80x faster)
#   Rust version: ~7ms (comparable)
#
require "crimage"
require "./raytracer/common"

width = 500
height = 500

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
