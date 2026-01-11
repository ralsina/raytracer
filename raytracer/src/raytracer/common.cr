# Shared raytracer engine
# Used by both raytracer.cr (benchmark) and animated.cr (real-time demo)

require "mutex"

struct Vector
  getter x : Float64
  getter y : Float64
  getter z : Float64

  def initialize(@x : Float64, @y : Float64, @z : Float64)
  end

  def scale(k : Float64) : Vector
    Vector.new(@x * k, @y * k, @z * k)
  end

  def -(other : Vector) : Vector
    Vector.new(@x - other.x, @y - other.y, @z - other.z)
  end

  def +(other : Vector) : Vector
    Vector.new(@x + other.x, @y + other.y, @z + other.z)
  end

  def dot(other : Vector) : Float64
    @x * other.x + @y * other.y + @z * other.z
  end

  def mag : Float64
    Math.sqrt(@x * @x + @y * @y + @z * @z)
  end

  def norm : Vector
    mag_val = mag
    return Vector.new(Float64::INFINITY, Float64::INFINITY, Float64::INFINITY) if mag_val == 0
    scale(1.0 / mag_val)
  end

  def cross(other : Vector) : Vector
    Vector.new(@y * other.z - @z * other.y, @z * other.x - @x * other.z, @x * other.y - @y * other.x)
  end
end

struct Color
  getter r : Float64
  getter g : Float64
  getter b : Float64

  def initialize(@r : Float64, @g : Float64, @b : Float64)
  end

  def scale(k : Float64) : Color
    Color.new(safe_mul(@r, k), safe_mul(@g, k), safe_mul(@b, k))
  end

  def +(other : Color) : Color
    Color.new(safe_add(@r, other.r), safe_add(@g, other.g), safe_add(@b, other.b))
  end

  def *(other : Color) : Color
    Color.new(safe_mul(@r, other.r), safe_mul(@g, other.g), safe_mul(@b, other.b))
  end

  private def safe_add(a : Float64, b : Float64) : Float64
    result = a + b
    # Check for overflow by comparing with infinity
    if result.abs > 1e100_f64
      # Clamp to maximum safe value
      (a > 0 ? 1.0_f64 : -1.0_f64) * 100.0_f64
    else
      result
    end
  end

  private def safe_mul(a : Float64, b : Float64) : Float64
    result = a * b
    # Check for overflow
    if result.abs > 1e100_f64
      # Clamp to maximum safe value
      (a * b > 0 ? 1.0_f64 : -1.0_f64) * 100.0_f64
    else
      result
    end
  end

  def self.to_drawing_color(c : Color) : Tuple(UInt8, UInt8, UInt8)
    r = (c.r.clamp(0.0, 1.0) * 255).to_u8
    g = (c.g.clamp(0.0, 1.0) * 255).to_u8
    b = (c.b.clamp(0.0, 1.0) * 255).to_u8
    {r, g, b}
  end

  # HSV to RGB conversion for color cycling
  def self.from_hsv(h : Float64, s : Float64, v : Float64) : Color
    h = h % 360.0
    c = v * s
    x = c * (1.0 - ((h / 60.0) % 2.0 - 1.0).abs)
    m = v - c

    if h < 60.0
      r, g, b = c, x, 0.0
    elsif h < 120.0
      r, g, b = x, c, 0.0
    elsif h < 180.0
      r, g, b = 0.0, c, x
    elsif h < 240.0
      r, g, b = 0.0, x, c
    elsif h < 300.0
      r, g, b = x, 0.0, c
    else
      r, g, b = c, 0.0, x
    end

    Color.new(r + m, g + m, b + m)
  end
end

COLOR_WHITE         = Color.new(1.0_f64, 1.0_f64, 1.0_f64)
COLOR_GREY          = Color.new(0.5_f64, 0.5_f64, 0.5_f64)
COLOR_BLACK         = Color.new(0.0_f64, 0.0_f64, 0.0_f64)
COLOR_BACKGROUND    = COLOR_BLACK
COLOR_DEFAULT_COLOR = COLOR_BLACK

module Surface
  abstract def diffuse(pos : Vector) : Color
  abstract def specular(pos : Vector) : Color
  abstract def reflect(pos : Vector) : Float64
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

  def reflect(pos : Vector) : Float64
    0.7_f64
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

  def reflect(pos : Vector) : Float64
    ((pos.z).floor.to_i + (pos.x).floor.to_i).odd? ? 0.1_f64 : 0.7_f64
  end

  def specular(pos : Vector) : Color
    COLOR_WHITE
  end

  def roughness : Int32
    250
  end
end

class MatteSurface
  include Surface

  def initialize(@color : Color)
  end

  def diffuse(pos : Vector) : Color
    @color
  end

  def reflect(pos : Vector) : Float64
    0.0_f64
  end

  def specular(pos : Vector) : Color
    COLOR_DEFAULT_COLOR
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
    down = Vector.new(0.0_f64, -1.0_f64, 0.0_f64)
    @pos = pos
    @forward = (look_at - @pos).norm
    @right = (@forward.cross(down)).norm.scale(1.5_f64)
    @up = (@forward.cross(@right)).norm.scale(1.5_f64)
  end
end

record Ray, start : Vector, dir : Vector
record Intersection, thing : Thing, ray : Ray, dist : Float64

module Thing
  abstract def normal(pos : Vector) : Vector
  abstract def surface : Surface
  abstract def intersect(ray : Ray) : Intersection?
end

class Sphere
  include Thing

  getter radius2 : Float64
  getter center : Vector

  def initialize(@center : Vector, radius : Float64, @surface : Surface)
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
    dist = 0.0_f64
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
  getter offset : Float64

  def initialize(@norm : Vector, @offset : Float64, @surface : Surface)
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
    closest = Float64::INFINITY
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

  def test_ray(ray : Ray, scene : Scene) : Float64?
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
    reflect_dir = d - (normal.scale(2.0_f64 * dot_val))
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

    lights.each do |light|
      ldis = light.pos - pos
      livec = ldis.norm
      neat_isect = test_ray(Ray.new(pos, livec), scene)

      is_in_shadow = neat_isect && neat_isect <= ldis.mag
      next if is_in_shadow

      illum = livec.dot(norm)
      next if illum <= 0

      lcolor = light.color.scale(illum)

      specular = livec.dot(rd.norm)
      if specular > 0
        # Safe pow to prevent overflow with large exponents
        spec_clamped = specular.clamp(0.0_f64, 0.99_f64)
        begin
          spec_pow = spec_clamped ** surface.roughness
          if !spec_pow.finite? || spec_pow.abs > 1e100_f64
            spec_pow = 1.0_f64
          end
          scolor = light.color.scale(spec_pow.clamp(0.0_f64, 1.0_f64))
        rescue
          scolor = COLOR_DEFAULT_COLOR
        end
      else
        scolor = COLOR_DEFAULT_COLOR
      end

      color = color + (surface.diffuse(pos) * lcolor) + (surface.specular(pos) * scolor)
    end

    color
  end

  def get_point(x : Int32, y : Int32, screen_width : Int32, screen_height : Int32, camera : Camera) : Vector
    recenter_x = (x - (screen_width * 0.5)) / (screen_width * 2)
    recenter_y = -(y - (screen_height * 0.5)) / (screen_height * 2)
    (camera.forward + (camera.right.scale(recenter_x) + camera.up.scale(recenter_y))).norm
  end

  def render(scene : Scene, width : Int32, height : Int32, samples : Int32 = 1) : Bytes
    num_threads = (ENV["CRYSTAL_WORKERS"]? || "8").to_i
    adaptive = (ENV["ADAPTIVE_AA"]? || "1").to_i != 0
    buffer = Bytes.new(width * height * 4)

    # Work stealing using a mutex-protected bitmap
    row_taken = Array.new(height, false)
    mutex = Mutex.new
    done_channel = Channel(Nil).new

    things = scene.things
    lights = scene.lights
    camera_pos = scene.camera.pos
    camera = scene.camera

    num_threads.times do |thread_idx|
      spawn do
        local_scene = Scene.new(things, lights, camera)
        cam_forward = camera.forward
        cam_right = camera.right
        cam_up = camera.up
        current_pos = thread_idx

        loop do
          # Find next unclaimed row using work stealing
          y = -1
          mutex.synchronize do
            while current_pos < height
              unless row_taken[current_pos]
                row_taken[current_pos] = true
                y = current_pos
                break
              end
              current_pos += 1
            end
          end

          # No more rows available
          break if y == -1

          row_offset = y * width * 4
          recenter_y = -((y - (height >> 1)) / (height << 1)).to_f64

          # Trace left edge of first pixel to initialize ray reuse cache
          jitter_left = -0.25_f64 / width
          jitter_right = 0.25_f64 / width
          jitter_top = -0.25_f64 / height
          jitter_bottom = 0.25_f64 / height

          # First pixel's left edge - we need to trace this
          first_recenter_x = ((0 - (width >> 1)) / (width << 1) + jitter_left).to_f64
          recenter_y_jittered = recenter_y + jitter_top
          ray_dir = (cam_forward + (cam_right.scale(first_recenter_x) + cam_up.scale(recenter_y_jittered))).norm
          prev_right_color = trace_ray(Ray.new(camera_pos, ray_dir), local_scene, 0)

          width.times do |x|
            r_sum = 0.0_f64
            g_sum = 0.0_f64
            b_sum = 0.0_f64
            actual_samples = 0

            if samples == 1
              # Single sample at center
              recenter_x = ((x - (width >> 1)) / (width << 1)).to_f64
              ray_dir = (cam_forward + (cam_right.scale(recenter_x) + cam_up.scale(recenter_y))).norm
              color = trace_ray(Ray.new(camera_pos, ray_dir), local_scene, 0)
              r_sum += color.r
              g_sum += color.g
              b_sum += color.b
              actual_samples = 1
            elsif adaptive
              # Adaptive mode with edge detection and ray reuse
              # Reuse previous pixel's right edge as our left edge
              color_left = prev_right_color

              # Always trace right edge (will be reused by next pixel)
              recenter_x = ((x - (width >> 1)) / (width << 1) + jitter_right).to_f64
              recenter_y_jittered = recenter_y + jitter_top
              ray_dir = (cam_forward + (cam_right.scale(recenter_x) + cam_up.scale(recenter_y_jittered))).norm
              color_right = trace_ray(Ray.new(camera_pos, ray_dir), local_scene, 0)
              prev_right_color = color_right

              # Check for edge: if left and right differ significantly, use more samples
              edge_threshold = 0.05_f64 / (samples.to_f64 ** 0.5_f64)
              color_diff = (color_left.r - color_right.r).abs +
                           (color_left.g - color_right.g).abs +
                           (color_left.b - color_right.b).abs

              if color_diff > edge_threshold && samples >= 4
                # Edge detected! Use 4 corner samples
                r_sum += color_left.r
                g_sum += color_left.g
                b_sum += color_left.b

                r_sum += color_right.r
                g_sum += color_right.g
                b_sum += color_right.b

                # Trace bottom corners
                recenter_x = ((x - (width >> 1)) / (width << 1) + jitter_left).to_f64
                recenter_y_jittered = recenter_y + jitter_bottom
                ray_dir = (cam_forward + (cam_right.scale(recenter_x) + cam_up.scale(recenter_y_jittered))).norm
                color = trace_ray(Ray.new(camera_pos, ray_dir), local_scene, 0)
                r_sum += color.r
                g_sum += color.g
                b_sum += color.b

                recenter_x = ((x - (width >> 1)) / (width << 1) + jitter_right).to_f64
                recenter_y_jittered = recenter_y + jitter_bottom
                ray_dir = (cam_forward + (cam_right.scale(recenter_x) + cam_up.scale(recenter_y_jittered))).norm
                color = trace_ray(Ray.new(camera_pos, ray_dir), local_scene, 0)
                r_sum += color.r
                g_sum += color.g
                b_sum += color.b

                actual_samples = 4
              else
                # No edge, just average the two samples we already have
                r_sum = (color_left.r + color_right.r) * 0.5_f64
                g_sum = (color_left.g + color_right.g) * 0.5_f64
                b_sum = (color_left.b + color_right.b) * 0.5_f64
                actual_samples = 1
              end
            else
              # Non-adaptive mode: full sampling for every pixel
              samples.times do |sample|
                # Deterministic jitter pattern
                sample_x = (sample * 7) % samples
                sample_y = (sample * 11) % samples
                jitter_x = (sample_x.to_f64 / samples.to_f64 - 0.5) / width
                jitter_y = (sample_y.to_f64 / samples.to_f64 - 0.5) / height

                recenter_x = ((x - (width >> 1)) / (width << 1) + jitter_x).to_f64
                recenter_y_jittered = recenter_y + jitter_y
                ray_dir = (cam_forward + (cam_right.scale(recenter_x) + cam_up.scale(recenter_y_jittered))).norm
                color = trace_ray(Ray.new(camera_pos, ray_dir), local_scene, 0)

                r_sum += color.r
                g_sum += color.g
                b_sum += color.b
              end
              actual_samples = samples
            end

            # Average the samples
            avg_color = Color.new(r_sum / actual_samples, g_sum / actual_samples, b_sum / actual_samples)

            offset = row_offset + (x * 4)
            buffer[offset] = (avg_color.r.clamp(0.0_f64, 1.0_f64) * 255).to_u8
            buffer[offset + 1] = (avg_color.g.clamp(0.0_f64, 1.0_f64) * 255).to_u8
            buffer[offset + 2] = (avg_color.b.clamp(0.0_f64, 1.0_f64) * 255).to_u8
            buffer[offset + 3] = 255_u8
          end
        end

        done_channel.send(nil)
      end
    end

    # Wait for all threads to complete
    num_threads.times { done_channel.receive }

    buffer
  end
end

class DefaultScene
  getter things : Array(Thing)
  getter lights : Array(Light)
  getter camera : Camera

  def initialize
    @things = [
      Plane.new(Vector.new(0.0_f64, 1.0_f64, 0.0_f64), 0.0_f64, SURFACE_CHECKERBOARD),
      Sphere.new(Vector.new(0.0_f64, 1.0_f64, -0.25_f64), 1.0_f64, SURFACE_SHINY),
      Sphere.new(Vector.new(-1.0_f64, 0.5_f64, 1.5_f64), 0.5_f64, SURFACE_SHINY),
    ] of Thing
    @lights = [
      Light.new(Vector.new(-2.0_f64, 2.5_f64, 0.0_f64), Color.new(0.49_f64, 0.07_f64, 0.07_f64)),
      Light.new(Vector.new(1.5_f64, 2.5_f64, 1.5_f64), Color.new(0.07_f64, 0.07_f64, 0.49_f64)),
      Light.new(Vector.new(1.5_f64, 2.5_f64, -1.5_f64), Color.new(0.07_f64, 0.49_f64, 0.071_f64)),
      Light.new(Vector.new(0.0_f64, 3.5_f64, 0.0_f64), Color.new(0.21_f64, 0.21_f64, 0.35_f64)),
    ]
    @camera = Camera.new(Vector.new(3.0_f64, 2.0_f64, 4.0_f64), Vector.new(-1.0_f64, 0.5_f64, 0.0_f64))
  end

  def to_scene : Scene
    Scene.new(@things, @lights, @camera)
  end
end
