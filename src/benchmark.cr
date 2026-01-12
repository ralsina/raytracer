# Raytracer - Ported from Ruby to Crystal
#
# Build options:
#   shards build --release -Dpreview_mt --mcpu=native --mcmodel=kernel
#
# Run with:
#   CRYSTAL_WORKERS=16 ./bin/raytracer
#
# Performance: <7ms for 500x500 image with 16 workers
# Comparison:
#   Ruby original: ~550ms
#   This Crystal version: ~7ms (~80x faster)
#   Rust version: ~7ms (comparable)
#
require "benchmark"
require "crimage"
require "mutex"
require "wait_group"

struct Vector
  getter x : Float32
  getter y : Float32
  getter z : Float32

  def initialize(@x : Float32, @y : Float32, @z : Float32)
  end

  @[AlwaysInline]
  def scale(k : Float32) : Vector
    Vector.new(@x * k, @y * k, @z * k)
  end

  @[AlwaysInline]
  def -(other : Vector) : Vector
    Vector.new(@x - other.x, @y - other.y, @z - other.z)
  end

  @[AlwaysInline]
  def +(other : Vector) : Vector
    Vector.new(@x + other.x, @y + other.y, @z + other.z)
  end

  @[AlwaysInline]
  def dot(other : Vector) : Float32
    @x * other.x + @y * other.y + @z * other.z
  end

  def mag : Float32
    Math.sqrt(@x * @x + @y * @y + @z * @z)
  end

  def norm : Vector
    mag_val = mag
    return Vector.new(Float32::INFINITY, Float32::INFINITY, Float32::INFINITY) if mag_val == 0
    scale(1.0_f32 / mag_val)
  end

  @[AlwaysInline]
  def cross(other : Vector) : Vector
    Vector.new(@y * other.z - @z * other.y, @z * other.x - @x * other.z, @x * other.y - @y * other.x)
  end
end

struct Color
  getter r : Float32
  getter g : Float32
  getter b : Float32

  def initialize(@r : Float32, @g : Float32, @b : Float32)
  end

  @[AlwaysInline]
  def scale(k : Float32) : Color
    Color.new(@r * k, @g * k, @b * k)
  end

  @[AlwaysInline]
  def +(other : Color) : Color
    Color.new(@r + other.r, @g + other.g, @b + other.b)
  end

  @[AlwaysInline]
  def *(other : Color) : Color
    Color.new(@r * other.r, @g * other.g, @b * other.b)
  end
end

COLOR_WHITE         = Color.new(1.0_f32, 1.0_f32, 1.0_f32)
COLOR_GREY          = Color.new(0.5_f32, 0.5_f32, 0.5_f32)
COLOR_BLACK         = Color.new(0.0_f32, 0.0_f32, 0.0_f32)
COLOR_BACKGROUND    = COLOR_BLACK
COLOR_DEFAULT_COLOR = COLOR_BLACK

module Surface
  abstract def diffuse(pos : Vector) : Color
  abstract def specular(pos : Vector) : Color
  abstract def reflect(pos : Vector) : Float32
  abstract def roughness : Int32
end

class ShinySurface
  include Surface

  def diffuse(pos : Vector) : Color
    COLOR_WHITE
  end

  def specular(pos : Vector) : Color
    COLOR_GREY
  end

  def reflect(pos : Vector) : Float32
    0.7_f32
  end

  def roughness : Int32
    250
  end
end

class CheckerboardSurface
  include Surface

  def diffuse(pos : Vector) : Color
    ((pos.z).floor.to_i + (pos.x).floor.to_i).odd? ? COLOR_WHITE : COLOR_BLACK
  end

  def reflect(pos : Vector) : Float32
    ((pos.z).floor.to_i + (pos.x).floor.to_i).odd? ? 0.1_f32 : 0.7_f32
  end

  def specular(pos : Vector) : Color
    COLOR_WHITE
  end

  def roughness : Int32
    250
  end
end

SURFACE_SHINY        = ShinySurface.new
SURFACE_CHECKERBOARD = CheckerboardSurface.new

class Camera
  getter pos : Vector
  getter forward : Vector
  getter right : Vector
  getter up : Vector

  def initialize(pos : Vector, look_at : Vector)
    down = Vector.new(0.0_f32, -1.0_f32, 0.0_f32)
    @pos = pos
    @forward = (look_at - @pos).norm
    @right = (@forward.cross(down)).norm.scale(1.5_f32)
    @up = (@forward.cross(@right)).norm.scale(1.5_f32)
  end
end

record Ray, start : Vector, dir : Vector
record Intersection, thing : Thing, ray : Ray, dist : Float32

module Thing
  abstract def normal(pos : Vector) : Vector
  abstract def surface : Surface
  abstract def intersect(ray : Ray) : Intersection?
end

class Sphere
  include Thing

  getter radius2 : Float32
  getter center : Vector

  def initialize(@center : Vector, radius : Float32, @surface : Surface)
    @radius2 = radius * radius
  end

  def normal(pos : Vector) : Vector
    (pos - @center).norm
  end

  def surface : Surface
    @surface
  end

  def intersect(ray : Ray) : Intersection?
    eo = @center - ray.start
    v = eo.dot(ray.dir)
    dist = 0.0_f32
    if v >= 0
      disc = @radius2 - (eo.dot(eo) - v * v)
      dist = v - Math.sqrt(disc) if disc >= 0
    end
    (dist == 0) ? nil : Intersection.new(self, ray, dist)
  end
end

class Plane
  include Thing

  getter norm : Vector
  getter offset : Float32

  def initialize(@norm : Vector, @offset : Float32, @surface : Surface)
  end

  def normal(pos : Vector) : Vector
    @norm
  end

  def intersect(ray : Ray) : Intersection?
    denom = @norm.dot(ray.dir)
    return nil if denom > 0
    dist = (@norm.dot(ray.start) + @offset) / (-denom)
    Intersection.new(self, ray, dist)
  end

  def surface : Surface
    @surface
  end
end

record Light, pos : Vector, color : Color

class Scene
  getter things : Array(Thing)
  getter lights : Array(Light)
  getter camera : Camera

  def initialize(@things : Array(Thing), @lights : Array(Light), @camera : Camera)
  end
end

class RayTracer
  MAX_DEPTH = 5

  def intersections(ray : Ray, scene : Scene) : Intersection?
    closest = Float32::INFINITY
    closest_inter = nil
    things = scene.things
    things.each do |item|
      inter = item.intersect(ray)
      if inter && inter.dist < closest
        closest_inter = inter
        closest = inter.dist
      end
    end
    closest_inter
  end

  def test_ray(ray : Ray, scene : Scene) : Float32?
    isect = intersections(ray, scene)
    isect && isect.dist
  end

  def trace_ray(ray : Ray, scene : Scene, depth : Int32) : Color
    isect = intersections(ray, scene)
    isect.nil? ? COLOR_BACKGROUND : shade(isect, scene, depth)
  end

  def shade(isect : Intersection, scene : Scene, depth : Int32) : Color
    d = isect.ray.dir
    pos = isect.ray.start + (d.scale(isect.dist))
    normal = isect.thing.normal(pos)
    dot_val = normal.dot(d)
    reflect_dir = d - (normal.scale(2.0_f32 * dot_val))
    natural_color = COLOR_BACKGROUND + get_natural_color(isect.thing, pos, normal, reflect_dir, scene)
    reflected_color = depth >= MAX_DEPTH ? COLOR_GREY : get_reflection_color(isect.thing, pos, normal, reflect_dir, scene, depth)
    natural_color + reflected_color
  end

  def get_reflection_color(thing : Thing, pos : Vector, normal : Vector, rd : Vector, scene : Scene, depth : Int32) : Color
    reflect_factor = thing.surface.reflect(pos)
    return COLOR_DEFAULT_COLOR if reflect_factor == 0
    (trace_ray(Ray.new(pos, rd), scene, depth + 1)).scale(reflect_factor)
  end

  def get_natural_color(thing : Thing, pos : Vector, norm : Vector, rd : Vector, scene : Scene) : Color
    color = COLOR_DEFAULT_COLOR
    lights = scene.lights
    surface = thing.surface
    roughness = surface.roughness  # Cache this, called 1M times per frame

    lights.each do |light|
      ldis = light.pos - pos
      ldist_sq = ldis.dot(ldis)  # Squared distance
      livec = ldis.norm
      neat_isect = test_ray(Ray.new(pos, livec), scene)

      # Compare squared distances to avoid sqrt
      is_in_shadow = neat_isect && (neat_isect * neat_isect) <= ldist_sq
      next if is_in_shadow

      illum = livec.dot(norm)
      next if illum <= 0

      lcolor = light.color.scale(illum)

      # rd is already normalized (reflection of unit vector), skip redundant norm()
      specular = livec.dot(rd)
      scolor = specular > 0 ? light.color.scale(specular ** roughness) : COLOR_DEFAULT_COLOR

      color = color + (surface.diffuse(pos) * lcolor) + (surface.specular(pos) * scolor)
    end

    color
  end

  def render(scene : Scene, width : Int32, height : Int32) : CrImage::RGBA
    buffer = Bytes.new(width * height * 4)
    render_to_buffer(scene, width, height, buffer)
    CrImage::RGBA.from_buffer(buffer, width, height)
  end

  def render_to_buffer(scene : Scene, width : Int32, height : Int32, buffer : Bytes) : Nil
    num_threads = (ENV["CRYSTAL_WORKERS"]? || "8").to_i

    # Work stealing using a mutex-protected row counter
    next_row = Atomic(Int32).new(0)
    wg = WaitGroup.new(num_threads)

    things = scene.things
    lights = scene.lights
    camera_pos = scene.camera.pos
    camera = scene.camera
    cam_forward = camera.forward
    cam_right = camera.right
    cam_up = camera.up

    num_threads.times do |thread_idx|
      spawn do
        local_scene = Scene.new(things, lights, camera)

        loop do
          # Get next row atomically
          y = next_row.add(1)
          break if y >= height

          row_offset = y * width * 4
          recenter_y = -((y - (height >> 1)) / (height << 1)).to_f32
          up_scaled = cam_up.scale(recenter_y)
          forward_plus_up = cam_forward + up_scaled  # Pre-compute, constant per row

          offset = row_offset
          width.times do |x|
            recenter_x = ((x - (width >> 1)) / (width << 1)).to_f32
            ray_dir = (forward_plus_up + cam_right.scale(recenter_x)).norm
            color = trace_ray(Ray.new(camera_pos, ray_dir), local_scene, 0)

            buffer[offset] = (color.r.clamp(0.0_f32, 1.0_f32) * 255).to_u8
            buffer[offset + 1] = (color.g.clamp(0.0_f32, 1.0_f32) * 255).to_u8
            buffer[offset + 2] = (color.b.clamp(0.0_f32, 1.0_f32) * 255).to_u8
            buffer[offset + 3] = 255_u8
            offset += 4
          end
        end

        wg.done
      end
    end

    # Wait for all threads to complete
    wg.wait

    # Create image from the filled buffer
    CrImage::RGBA.from_buffer(buffer, width, height)
  end
end

class DefaultScene
  getter things : Array(Thing)
  getter lights : Array(Light)
  getter camera : Camera

  def initialize
    @things = [
      Plane.new(Vector.new(0.0_f32, 1.0_f32, 0.0_f32), 0.0_f32, SURFACE_CHECKERBOARD),
      Sphere.new(Vector.new(0.0_f32, 1.0_f32, -0.25_f32), 1.0_f32, SURFACE_SHINY),
      Sphere.new(Vector.new(-1.0_f32, 0.5_f32, 1.5_f32), 0.5_f32, SURFACE_SHINY),
    ] of Thing
    @lights = [
      Light.new(Vector.new(-2.0_f32, 2.5_f32, 0.0_f32), Color.new(0.49_f32, 0.07_f32, 0.07_f32)),
      Light.new(Vector.new(1.5_f32, 2.5_f32, 1.5_f32), Color.new(0.07_f32, 0.07_f32, 0.49_f32)),
      Light.new(Vector.new(1.5_f32, 2.5_f32, -1.5_f32), Color.new(0.07_f32, 0.49_f32, 0.071_f32)),
      Light.new(Vector.new(0.0_f32, 3.5_f32, 0.0_f32), Color.new(0.21_f32, 0.21_f32, 0.35_f32)),
    ]
    @camera = Camera.new(Vector.new(3.0_f32, 2.0_f32, 4.0_f32), Vector.new(-1.0_f32, 0.5_f32, 0.0_f32))
  end

  def to_scene : Scene
    Scene.new(@things, @lights, @camera)
  end
end

width = 500
height = 500

default_scene = DefaultScene.new
scene = default_scene.to_scene
ray_tracer = RayTracer.new

puts "Benchmarking #{width}x#{height} render..."
puts "Workers: #{(ENV["CRYSTAL_WORKERS"]? || "8")}"
puts ""

# Pre-allocate buffer for benchmarking
benchmark_buffer = Bytes.new(width * height * 4)

Benchmark.ips(warmup: 4.seconds, calculation: 10.seconds) do |x|
  x.report("render") do
    ray_tracer.render_to_buffer(scene, width, height, benchmark_buffer)
  end
end

# Save one image for verification
img = ray_tracer.render(scene, width, height)
CrImage::PNG.write("crystal-raytracer.png", img)
