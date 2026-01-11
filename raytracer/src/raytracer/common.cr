# Shared raytracer engine
# Used by both raytracer.cr (benchmark) and animated.cr (real-time demo)

require "mutex"

struct Vector
  getter x : Float32
  getter y : Float32
  getter z : Float32

  def initialize(@x : Float32, @y : Float32, @z : Float32)
  end

  def scale(k : Float32) : Vector
    Vector.new(@x * k, @y * k, @z * k)
  end

  def -(other : Vector) : Vector
    Vector.new(@x - other.x, @y - other.y, @z - other.z)
  end

  def +(other : Vector) : Vector
    Vector.new(@x + other.x, @y + other.y, @z + other.z)
  end

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

  def scale(k : Float32) : Color
    Color.new(@r * k, @g * k, @b * k)
  end

  def +(other : Color) : Color
    Color.new(@r + other.r, @g + other.g, @b + other.b)
  end

  def *(other : Color) : Color
    Color.new(@r * other.r, @g * other.g, @b * other.b)
  end

  def self.to_drawing_color(c : Color) : Tuple(UInt8, UInt8, UInt8)
    r = (c.r.clamp(0.0_f32, 1.0_f32) * 255).to_u8
    g = (c.g.clamp(0.0_f32, 1.0_f32) * 255).to_u8
    b = (c.b.clamp(0.0_f32, 1.0_f32) * 255).to_u8
    {r, g, b}
  end

  # HSV to RGB conversion for color cycling
  def self.from_hsv(h : Float32, s : Float32, v : Float32) : Color
    h = h % 360.0_f32
    c = v * s
    x = c * (1.0_f32 - ((h / 60.0_f32) % 2.0_f32 - 1.0_f32).abs)
    m = v - c

    if h < 60.0_f32
      r, g, b = c, x, 0.0_f32
    elsif h < 120.0_f32
      r, g, b = x, c, 0.0_f32
    elsif h < 180.0_f32
      r, g, b = 0.0_f32, c, x
    elsif h < 240.0_f32
      r, g, b = 0.0_f32, x, c
    elsif h < 300.0_f32
      r, g, b = x, 0.0_f32, c
    else
      r, g, b = c, 0.0_f32, x
    end

    Color.new(r + m, g + m, b + m)
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
      scolor = specular > 0 ? light.color.scale(specular ** surface.roughness) : COLOR_DEFAULT_COLOR

      color = color + (surface.diffuse(pos) * lcolor) + (surface.specular(pos) * scolor)
    end

    color
  end

  def get_point(x : Int32, y : Int32, screen_width : Int32, screen_height : Int32, camera : Camera) : Vector
    recenter_x = (x - (screen_width * 0.5)) / (screen_width * 2)
    recenter_y = -(y - (screen_height * 0.5)) / (screen_height * 2)
    (camera.forward + (camera.right.scale(recenter_x) + camera.up.scale(recenter_y))).norm
  end

  def render(scene : Scene, width : Int32, height : Int32) : Bytes
    num_threads = (ENV["CRYSTAL_WORKERS"]? || "8").to_i
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
          recenter_y = -((y - (height >> 1)) / (height << 1)).to_f32
          up_scaled = cam_up.scale(recenter_y)

          width.times do |x|
            recenter_x = ((x - (width >> 1)) / (width << 1)).to_f32
            ray_dir = (cam_forward + (cam_right.scale(recenter_x) + up_scaled)).norm
            color = trace_ray(Ray.new(camera_pos, ray_dir), local_scene, 0)

            offset = row_offset + (x * 4)
            buffer[offset] = (color.r.clamp(0.0_f32, 1.0_f32) * 255).to_u8
            buffer[offset + 1] = (color.g.clamp(0.0_f32, 1.0_f32) * 255).to_u8
            buffer[offset + 2] = (color.b.clamp(0.0_f32, 1.0_f32) * 255).to_u8
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
