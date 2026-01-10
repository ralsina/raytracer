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

## Build

```bash
shards build --release -Dpreview_mt --mcpu=native --mcmodel=kernel
```

## Run

```bash
CRYSTAL_WORKERS=16 ./bin/raytracer
```

Output: `crystal-raytracer.png`

## Optimization Journey

See [the blog post](https://ralsina.me/weblog/posts/chasing-rust-how-a-crystal-raytracer-got-80x-faster.html) for the full story of how we got from Ruby to Rust-speed in Crystal.

## License

MIT
