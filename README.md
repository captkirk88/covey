# Covey

Covey is a C3 project that implements a simple ECS (Entity Component System) framework inspired by Bevy. It is designed to be lightweight and easy to use.

Covey is a work in progress and is not yet feature complete but can be used to create simple games and simulations. Expect changes to the API as it evolves.

> [!NOTE]
> C3 does not have a good std fully implemented yet and some of the c3c commands are not implemented yet.  My advice, wait for 1.0 before using it in a project.

## Docs

Generate docs with `c3c docgen --emit-stdlib=no`.

## Benchmarks

Run benchmarks with `c3c test --benchmarking -O5`.

> [!NOTE]
> Results on my system are not representative of all systems. Your results may vary.

```
test_world::bench_world_query ...........  132.59us avg,  12.35us sd,   423509.81 CPU clocks,   10000 iters in    1.33s
test_world::bench_spawn_add_components ..    2.65us avg,   2.11us sd,     8467.13 CPU clocks,   10000 iters in  26.51ms
test_world::bench_3_systems_execution ...  423.68us avg,  15.95us sd,  1353232.12 CPU clocks,   10000 iters in    4.24s
```

Each benchmark was ran with 100,000 entities.

Performance could be improved.

## Building

It isn't necessary to build the project, but if you want to build it, you can use the following command:

```bash
c3c build --no-entry -O5 --show-backtrace=yes --panic-msg=yes
```

> [!NOTE]
> Optional to have yes/no on backtrace and panic messages. Your choice.

Keep in mind the header is missing essential macros that only C3 provides, otherwise, you can link the library to your project and use it as a dependency in C or C++.

### Preferred Approach

Use https://github.com/konimarti/c3l

```bash
c3l fetch https://github.com/captkirk88/covey
```

## LICENSE

[MIT](LICENSE)
