# crys

A Crystal one-liner tool.

It does four things only.

- decide how input is iterated
- decide what each record sees
- decide what to require
- decide how output is emitted

It does not add dependency management or a custom DSL. It is a thin wrapper around plain Crystal code.

## Installation

Build:

```sh
shards build
```

Binary:

```sh
bin/crys
```

Move it somewhere on your PATH if needed.

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

## Options

- `-n`: read input line by line. Exposes `line` and `nr`
- `-p`: same as `-n`, but assigns the body result back to `line` and prints it
- `-a`: auto-split `line` into `f`
- `-F SEP`: field separator for `-a`
- `-g`, `--slurp`: read all input into `input`
- `-i[SUFFIX]`: edit files in place. `-i.bak` creates backups
- `-r LIB`: add `require "LIB"`. Repeatable
- `--init CODE`: insert code before the main body or loop
- `--final CODE`: insert code after the main body or loop
- `--dump`: print the generated Crystal code and exit
- `-O LEVEL`: run with optimization level (`0`, `1`, `2`, `3`, `s`, `z`)
- `--release`: run with `crystal run --release`
- `--error-trace`: run with `crystal run --error-trace`
- `-h`, `--help`: show help

Implicit variables:

- `line`: current line, always chomped
- `f`: split fields, only with `-a`
- `nr`: record number
- `input`: full slurped input, only with `-g` or `--slurp`
- `path`: current file path when reading files or editing in place

Constraints:

- `-g` / `--slurp` cannot be combined with `-n` / `-p`
- `-i` requires at least one file

## Development

Run unit tests:

```sh
crystal spec
```

Run integration tests:

```sh
bash spec/integration_test.sh
```

Build locally:

```sh
crystal build src/main.cr -o bin/crys
```
