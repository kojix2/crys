# crys

[![test](https://github.com/kojix2/crys/actions/workflows/test.yml/badge.svg)](https://github.com/kojix2/crys/actions/workflows/test.yml)

:construction: Very early stage

A command-line tool that can process text files ranging from a few hundred megabytes to several gigabytes with a single command. 
It uses a Ruby-like syntax and is about as fast as C.

## Installation

Build from source:

```sh
git clone https://github.com/kojix2/crys
cd crys
shards build
mv bin/crys ~/.local/bin
```

Q: Building from source? Why don’t you distribute pre-compiled binary files?

A: This tool only works in environments where the Crystal compiler is available. If the Crystal code cannot be compiled, Crys will not run. That’s why this approach works.

## Usage

Basic form:

```sh
crys [options] 'CRYSTAL_CODE' [file ...]
```

Process stdin line by line:

```sh
printf 'a\nb\n' | crys -n 'puts l.upcase'
```

Assign the result back to `l` and print it:

```sh
printf 'a\nb\n' | crys -p 'l.upcase'
```

Auto-split input:

```sh
printf 'a:b\nc:d\n' | crys -a -F: 'puts f[1]'
```

Auto-split input with regex separator:

```sh
printf 'a:  b\nc:   d\n' | crys -a -F'/: +/' 'puts f[1]'
```

Read a full JSON document from input:

```sh
printf '{"a":1}' | crys -r json 'puts JSON.parse(ARGF)["a"].as_i'
```

Run setup and teardown code:

```sh
printf '1\n2\n3\n' | crys --init 'sum = 0' -n 'sum += l.to_i' --final 'puts sum'
```

Edit files in place:

```sh
crys -I .bak -p 'l.gsub("foo", "bar")' file.txt
crys -i -p 'l.upcase' file.txt
```

Inspect generated code:

```sh
crys --dump -p 'l.upcase'
```

Filter lines with repeatable preconditions:

```sh
printf 'ok\nerror\nwarn\n' | crys -n --where 'l =~ /err|warn/' 'puts l'
```

Use shortcut selectors and mappers:

```sh
printf 'a\nb\n' | crys --select 'l == "a"'
printf 'a\nb\n' | crys --map 'l.upcase'
```

Bind split fields to names:

```sh
printf 'alice:20\nbob:30\n' | crys -a -F: -N name,age 'puts "#{name}:#{age}"'
```

Use header-based access:

```sh
printf 'name,age\nalice,20\n' | crys -a -F, --header --map 'row["name"]'
```

Aggregate quickly without boilerplate:

```sh
printf '1\n2\n3\n' | crys --sum 'l.to_i'
printf 'ok\nerr\nwarn\n' | crys --where 'l =~ /err|warn/' --count
printf '1\nfoo\n3\n' | crys --where 'l =~ /^[0-9]+$/' --sum 'l.to_i' --count
```

## Options

- `-n`: read input line by line. Exposes `l`, `nr`, and `fnr`
- `-p`: same as `-n`, but assigns the body result back to `l` and prints it
- `-a`: auto-split `l` into `f` and expose `nf`
- `-F SEP`: field separator for `-a`. Prefix with `/` and suffix with `/` to use a regex: `-F'/: +/'`
- `-N NAMES`: bind split fields to variable names. Example: `-N name,count`
- `--where COND`: pre-filter condition in line mode. Repeatable, combined with AND
- `--map EXPR`: shortcut for line mode mapping (`puts(EXPR)`)
- `--select COND`: shortcut for line mode filtering (`puts l if COND`)
- `-h`, `--header`: treat first row as header and expose `row` hash (requires `-a`)
- `--sum EXPR`: sum expression across selected rows; exposes `__crys_sum`
- `--count`: count selected rows; exposes `__crys_count`
- `-i`: edit files in place without backup
- `-I SUFFIX`: edit files in place and keep backups with `SUFFIX`
- `-r LIB`: add `require "LIB"` to the generated program. Resolution is done from `CRYS_HOME`
- `--init CODE`: insert code before the main body or loop
- `--final CODE`: insert code after the main body or loop
- `--dump`: print the generated Crystal code and exit
- `-O LEVEL`: build with optimization level (`0`, `1`, `2`, `3`, `s`, `z`)
- `--release`: build with `crystal build --release`
- `--error-trace`: build with `crystal build --error-trace`
- `--version`: show tool version
- `--help`: show help

## Implicit Variables

- `l`: current line, always chomped
- `f`: split fields, only with `-a`
- `nf`: number of fields (`f.size`), only with `-a`
- `nr`: record number (global, counts across all files)
- `fnr`: per-file record number (same as `nr` for stdin, resets to 1 at each new file)
- `path`: current file path when reading files or editing in place
- `row`: `Hash(String, String)` mapped from header columns, only with `--header`

## Dependency Resolution (CRYS_HOME)

`crys` builds and runs generated programs under `CRYS_HOME` (default: `~/.local/share/crys`).
When you use `-r LIB`, dependency resolution is performed from this directory.

Typical setup:

```sh
export CRYS_HOME="$HOME/.local/share/crys"
mkdir -p "$CRYS_HOME"
cd "$CRYS_HOME"
shards init
vi shard.yml # Add your favorite shards
shards install
```

Then:

```sh
printf '{"a":1}' | crys -r json 'puts JSON.parse(ARGF)["a"].as_i'
```

## Caching

Generated programs are cached under `CRYS_HOME/cache` and reused when the generated code and Crystal flags are unchanged.

## Constraints

- `-i` requires at least one file
- `--map` and `--select` cannot be combined
- `--map` / `--select` cannot be combined with explicit `CRYSTAL_CODE`
- `-N` requires `-a`
- `--header` requires `-a`
- `--sum` / `--count` cannot be combined with explicit `CRYSTAL_CODE`

## Development

Run unit tests:

```sh
crystal spec
```

Run integration tests:

```sh
bash spec/integration_test.sh
```
