# Chasing Rust: How a Crystal Raytracer Got 80x Faster

I ported a raytracer from Ruby to Crystal. It didn't quite go as I expected. I had this idea that Crystal, being a compiled language, would blow Ruby out of the water. And it did! But then I looked at the Rust version and got... jealous.

This is the story of how I made a Ruby raytracer go from ~550ms to under 7ms, matching Rust performance. Along the way, I saved every version so you can see the evolution.

## The Code Archive

I've saved intermediate versions of the code on [Pasto](https://pasto1.ralsina.me):
- [v1](https://pasto1.ralsina.me/2d22e2a5-e8ca-470c-9886-6eaa4ae584df.1) - Early parallel version with per-thread buffers
- [v2](https://pasto1.ralsina.me/2d22e2a5-e8ca-470c-9886-6eaa4ae584df.2) - Using records instead of custom structs
- [v3](https://pasto1.ralsina.me/2d22e2a5-e8ca-470c-9886-6eaa4ae584df.3) - Float32 optimization
- [v4](https://pasto1.ralsina.me/2d22e2a5-e8ca-470c-9886-6eaa4ae584df.4) - Interleaved row assignment
- [v5](https://pasto1.ralsina.me/2d22e2a5-e8ca-470c-9886-6eaa4ae584df.5) - Channel-based work stealing (failed)
- [v6](https://pasto1.ralsina.me/2d22e2a5-e8ca-470c-9886-6eaa4ae584df.6) - Chunked work stealing (still slow)
- [v7](https://pasto1.ralsina.me/2d22e2a5-e8ca-470c-9886-6eaa4ae584df.7) - Back to static assignment
- [v8](https://pasto1.ralsina.me/2d22e2a5-e8ca-470c-9886-6eaa4ae584df.8) - Final: mutex-based work stealing

The final code is on [GitHub](https://github.com/ralsina/raytracer).

## The Baseline

The original Ruby raytracer from [github.com/edin/raytracer](https://github.com/edin/raytracer) renders a 500x500 image with spheres, planes, reflections, shadows, and multiple colored lights. On my machine, it takes about **550ms**.

That's not terrible for a pure Ruby implementation, but we can do better.

## First Pass: The Naive Port (v1)

I did a straightforward port to Crystal, adding type annotations and using the crimage library for PNG output. I used `class` for everything and Float64 by default. Added simple parallel rendering with per-thread buffers collected via channels.

**Result:** ~270ms

That's already a 2x speedup just from switching languages! But a Rust version of the same raytracer does it in ~7ms. We're still 40x slower. Something is very wrong.

## Structs vs Classes + Records (v2-v3)

I remembered that Crystal structs are value types (stack-allocated) while classes are reference types (heap-allocated). Changed Vector, Color, Ray, and Intersection to structs. Then I switched to using `record` for Ray, Intersection, and Light—which are just simple data holders.

Also switched from Float64 to Float32 throughout, matching the Rust version.

**Result:** ~100ms single-threaded, ~20ms with 8 threads

Much better! But we're still 3x slower than Rust.

## Parallel Rendering with Load Balancing (v4)

At this point I had 8-thread parallel rendering working, but when I instrumented each thread's timing, I saw a problem:

```
Thread 0: 5.7 ms
Thread 2: 8.6 ms
```

The total time was ~9ms, dominated by the slowest thread. The fast threads spent 3ms idle waiting. The problem: some rows are computationally expensive (lots of reflections) while others are simple (just background). Horizontal strips meant some threads got all the hard work.

I switched to **interleaved assignment**: thread 0 gets rows 0, 8, 16, 24... thread 1 gets rows 1, 9, 17, 25... and so on. This spreads complex and simple pixels evenly.

**Result:** ~9ms

## Work Stealing Attempt #1: Channels (v5 - FAILED)

I tried implementing work stealing using Crystal's channels. Threads would grab rows from a shared queue. Fast threads could steal work from slower ones.

**Result:** ~10ms (slower!)

The channel synchronization overhead was eating all the gains. I tried chunking (assigning 8 or 16 rows at a time) but it never beat static assignment.

## Work Stealing Attempt #2: Mutex-Protected Bitmap (v8 - SUCCESS!)

Then I had an idea. What if I used a simple array of booleans to track which rows were taken, protected by a mutex? No channels, no fancy stuff.

```crystal
row_taken = Array.new(height, false)
mutex = Mutex.new

loop do
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
  break if y == -1
  # ... render row y ...
end
```

Each thread scans forward from its current position, claiming unclaimed rows. When they finish their work, they keep scanning for more. Fast threads naturally steal work from slow ones.

**Result:** < 7ms with 16 workers

We did it! We're matching Rust performance!

## The Final Tally

| Version | Time | Speedup |
|---------|------|---------|
| Ruby original | 550ms | 1x |
| Naive Crystal port | 270ms | 2x |
| Structs + records + Float32 | ~20ms (8 threads) | 27x |
| Interleaved rows | ~9ms | 61x |
| Mutex work stealing (16 workers) | <7ms | **80x** |

## What I Learned

1. **Structs matter:** In Crystal, choosing struct vs class isn't just style—it's a performance decision.
2. **Measure everything:** I wouldn't have found the load imbalance without instrumentation.
3. **Channels have overhead:** Work stealing is a great concept, but channel operations in Crystal aren't free.
4. **Sometimes simple wins:** A mutex-protected array beat fancy channel-based work stealing.
5. **Float32 is fast enough:** Switching from Float64 to Float32 helped memory usage and cache efficiency.

## The Code

The final implementation is on [GitHub](https://github.com/ralsina/raytracer). Clone it and run:

```bash
git clone https://github.com/ralsina/raytracer
cd raytracer
shards build --release -Dpreview_mt --mcpu=native --mcmodel=kernel
CRYSTAL_WORKERS=16 ./bin/raytracer
```

And that's it. From Ruby to Rust-speed in Crystal, one optimization at a time. Is there room for more? Probably. But at under 7ms for a 500x500 raytrace, I'm calling it done.
