# Crystal Raytracer

A raytracer ported from Ruby to Crystal, optimized to match Rust performance.

## Original

Ported from [github.com/edin/raytracer](https://github.com/edin/raytracer) (Ruby version).

## Performance

Renders a 500x500 image with reflections, shadows, and multiple colored lights:

| Version | Time | Speedup |
|---------|------|---------|
| Ruby original | ~550ms | 1x |
| Crystal (final) | <7ms | **80x faster** |
| Rust version | ~7ms | comparable |

That you can see using the "benchmark" binary. However, that binary (while equivalent
to the others in the original benchmark repo) is buggy (like others in the original
benchmark repo) in that outside this very specific scene they are vulnerable to arithmetic
overflows and other issues.

The other binaries (including "raytracer") which renders the same scene do
proper bounds checking and are slightly slower.

Both "raytracer" and "animated" are also configurable using env vars, 
which may make them slower or faster.

## Build

```bash
shards build --release -Dpreview_mt --mcpu=native --mcmodel=kernel
```

## Run

```bash
CRYSTAL_WORKERS=16 ./bin/raytracer
CRYSTAL_WORKERS=16 ./bin/benchmark
CRYSTAL_WORKERS=16 ./bin/animated
```

Output: `crystal-raytracer.png`

## Optimization Journey

See [the blog post](https://ralsina.me/weblog/posts/making-code-80x-faster-step-by-step.html) for the full story of how we got from Ruby to Rust-speed in Crystal.

## License

MIT
