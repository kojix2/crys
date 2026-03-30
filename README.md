# crys

A Crystal one-liner tool.

[![test](https://github.com/kojix2/crys/actions/workflows/test.yml/badge.svg)](https://github.com/kojix2/crys/actions/workflows/test.yml)

## Installation

Build from source:

```sh
git clone https://github.com/kojix2/crys
cd crys
shards build
mv bin/crys ~/.local/bin
```

## Usage

Basic form:

```sh
crys [options] 'CRYSTAL_CODE' [file ...]
```

Process stdin line by line:

```sh
printf 'a\nb\n' | crys -n 'puts line.upcase'
```

Assign the result back to `line` and print it:

```sh
printf 'a\nb\n' | crys -p 'line.upcase'
```

Auto-split input:

```sh
printf 'a:b\nc:d\n' | crys -a -F: 'puts f[1]'
```

Auto-split input with regex separator:

```sh
printf 'a:  b\nc:   d\n' | crys -a -F'/: +/' 'puts f[1]'
```

Slurp all input:

```sh
printf '{"a":1}' | crys -r json -g 'puts JSON.parse(input)["a"].as_i'
```

Run setup and teardown code:

```sh
printf '1\n2\n3\n' | crys --init 'sum = 0' -n 'sum += line.to_i' --final 'puts sum'
```

Edit files in place:

```sh
crys -pi.bak 'line.gsub("foo", "bar")' file.txt
crys -i 'line.upcase' file.txt
```

Inspect generated code:

```sh
crys --dump -p 'line.upcase'
```

Filter lines with repeatable preconditions:

```sh
printf 'ok\nerror\nwarn\n' | crys -n --where 'line =~ /err|warn/' 'puts line'
```

Use shortcut selectors and mappers:

```sh
printf 'a\nb\n' | crys --select 'line == "a"'
printf 'a\nb\n' | crys --map 'line.upcase'
```

Bind split fields to names:

```sh
printf 'alice:20\nbob:30\n' | crys -a -F: -N name,age 'puts "#{name}:#{age}"'
```

## Options

- `-n`: read input line by line. Exposes `line`, `nr`, and `fnr`
- `-p`: same as `-n`, but assigns the body result back to `line` and prints it
- `-a`: auto-split `line` into `f` and expose `nf`
- `-F SEP`: field separator for `-a`. Prefix with `/` and suffix with `/` to use a regex: `-F'/: +/'`
- `-N NAMES`: bind split fields to variable names. Example: `-N name,count`
- `--where COND`: pre-filter condition in line mode. Repeatable, combined with AND
- `--map EXPR`: shortcut for line mode mapping (`puts(EXPR)`)
- `--select COND`: shortcut for line mode filtering (`puts line if COND`)
- `-g`, `--slurp`: read all input into `input`
- `-i[SUFFIX]`: edit files in place. `-i.bak` creates backups
- `-r LIB`: add `require "LIB"`. Repeatable
- `--init CODE`: insert code before the main body or loop
- `--final CODE`: insert code after the main body or loop
- `--dump`: print the generated Crystal code and exit
- `-O LEVEL`: build with optimization level (`0`, `1`, `2`, `3`, `s`, `z`)
- `--release`: build with `crystal build --release`
- `--error-trace`: build with `crystal build --error-trace`
- `-h`, `--help`: show help

Implicit variables:

- `line`: current line, always chomped
- `f`: split fields, only with `-a`
- `nf`: number of fields (`f.size`), only with `-a`
- `nr`: record number (global, counts across all files)
- `fnr`: per-file record number (same as `nr` for stdin, resets to 1 at each new file)
- `input`: full slurped input, only with `-g` or `--slurp`
- `path`: current file path when reading files or editing in place

Generated programs are cached under `CRYS_HOME/cache` and reused when the generated code and Crystal flags are unchanged.

Constraints:

- `-g` / `--slurp` cannot be combined with `-n` / `-p`
- `-i` requires at least one file
- `--map` and `--select` cannot be combined
- `--map` / `--select` cannot be combined with explicit `CRYSTAL_CODE`
- `-N` requires `-a`

## Development

Run unit tests:

```sh
crystal spec
```

Run integration tests:

```sh
bash spec/integration_test.sh
```
