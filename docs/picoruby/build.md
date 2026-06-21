# Building PicoRuby under `tmp/`

This project keeps external build work under `tmp/`. The repository
`.gitignore` already ignores `tmp/`, so the PicoRuby source tree, submodules,
and build artifacts are not tracked by this project.

The steps below describe the build performed on macOS for the POSIX PicoRuby
binary (`bin/picoruby`).

## Prerequisites

- C toolchain (`clang`/`gcc`)
- `git`
- CRuby 3.4 or newer
- Homebrew `openssl@3` on macOS

The system Ruby on macOS may be too old. In this environment, `/usr/bin/ruby`
was Ruby 2.6 and failed to run the PicoRuby build scripts. Ruby 3.4.3 from
`mise` was used instead.

## Clone PicoRuby

From this repository root:

```sh
mkdir -p tmp
git clone https://github.com/picoruby/picoruby.git tmp/picoruby
cd tmp/picoruby
git submodule update --init --recursive
```

`git clone --recurse-submodules` can be used instead of running the submodule
command separately.

## Build

Run `rake` through the Ruby 3.4 interpreter, not through the system `rake`
executable. On macOS, pass Homebrew OpenSSL include and library paths:

```sh
mise exec ruby@3.4.3 -- ruby -S rake \
  LDFLAGS=-L/opt/homebrew/opt/openssl@3/lib \
  CFLAGS=-I/opt/homebrew/opt/openssl@3/include
```

This creates:

```text
tmp/picoruby/bin/picoruby
tmp/picoruby/bin/mrbc-prism
tmp/picoruby/bin/r2p2
```

The `bin/*` files are symlinks to `tmp/picoruby/build/host/bin/*`.

## Verify

```sh
cd tmp/picoruby
./bin/picoruby -e 'puts "Hello World!"'
```

Expected output:

```text
Hello World!
```

## Issues Encountered

### `undefined local variable or method '_1'`

Running plain `rake` used `/Library/Ruby` / system Ruby 2.6:

```text
NameError: undefined local variable or method `_1'
```

PicoRuby requires CRuby 3.4 or newer. Use:

```sh
mise exec ruby@3.4.3 -- ruby -S rake
```

Using `ruby -S rake` matters because the `rake` executable itself may be
installed for the old system Ruby.

### `ld: library 'ssl' not found`

On macOS, the first Ruby 3.4 build reached the link step and then failed:

```text
ld: library 'ssl' not found
```

Homebrew does not link OpenSSL into the default system paths, so pass explicit
paths:

```sh
LDFLAGS=-L/opt/homebrew/opt/openssl@3/lib
CFLAGS=-I/opt/homebrew/opt/openssl@3/include
```

If Homebrew is installed somewhere else, check the path with:

```sh
brew --prefix openssl@3
```

## Notes

The command above builds the host/POSIX PicoRuby binary. For firmware targeting
RP2040/RP2350 boards, use a PicoRuby cross-compilation build config such as
`build_config/r2p2-picoruby-pico.rb` inside the PicoRuby source tree and the
required Pico SDK toolchain.
