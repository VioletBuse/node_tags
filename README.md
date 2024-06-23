# node_tags

[![Package Version](https://img.shields.io/hexpm/v/node_tags)](https://hex.pm/packages/node_tags)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/node_tags/)

```sh
gleam add node_tags
```
```gleam
import node_tags
import gleam/erlang/atom
import gleam/io

pub fn main() {
  let manager = atom.create_from_string("tags")
  |> node_tags.start

  node_tags.set(manager, "id", node_tags.String("main_node"))
  io.debug(
    node_tags.get_nodes_tagged(
      manager,
      where: #("id", node_tags.String("worker_node")),
      until: 1000
    )
  )
}
```

Further documentation can be found at <https://hexdocs.pm/node_tags>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
gleam shell # Run an Erlang shell
```
