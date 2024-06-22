import decipher
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/node.{type Node}
import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result

pub type Value {
  String(String)
  Int(Int)
  Float(Float)
  Bool(Bool)
  Null(Nil)
}

fn value_from_dynamic(dyn: Dynamic) -> Result(Value, List(dynamic.DecodeError)) {
  decipher.tagged_union(dynamic.element(0, atom.from_dynamic), [
    #(
      atom.create_from_string("string"),
      dynamic.decode1(String, dynamic.element(1, dynamic.string)),
    ),
    #(
      atom.create_from_string("int"),
      dynamic.decode1(Int, dynamic.element(1, dynamic.int)),
    ),
    #(
      atom.create_from_string("float"),
      dynamic.decode1(Float, dynamic.element(1, dynamic.float)),
    ),
    #(
      atom.create_from_string("bool"),
      dynamic.decode1(Bool, dynamic.element(1, dynamic.bool)),
    ),
    #(atom.create_from_string("null"), fn(_) { Ok(Null(Nil)) }),
  ])(dyn)
}

pub opaque type TagManager {
  TagManager(actor: Subject(Message))
}

/// Start a tag management process. This can fail if there is already another process with
/// the same name.
pub fn start(name: Atom) {
  let assert Ok(actor) =
    actor.start(State(name, dict.new(), dict.new()), handle_message)
  let assert Ok(_) = process.register(process.subject_owner(actor), name)
  process.send(actor, Initialize(actor))

  TagManager(actor)
}

type State {
  State(
    name: Atom,
    tags: Dict(String, Value),
    nodes: Dict(Node, Dict(String, Value)),
  )
}

pub opaque type Message {
  Initialize(self: Subject(Message))
  Tick(self: Subject(Message))
  SetTag(key: String, value: Value)
  DeleteTag(key: String)
  GetTags(client: Subject(List(#(String, Value))))
  Nodes(client: Subject(List(#(Node, Dict(String, Value)))))
  TaggedNodes(
    client: Subject(List(#(Node, Dict(String, Value)))),
    tag: #(String, Value),
  )
  MultipleUpdates(List(Message))
  InternalUpdateTag(node: Node, tag: #(String, Option(Value)))
}

fn handle_message(message: Message, state: State) -> actor.Next(Message, State) {
  case message {
    Initialize(..) -> handle_init(message, state)
    Tick(..) -> handle_tick(message, state)
    SetTag(..) -> handle_set_tag(message, state)
    DeleteTag(..) -> handle_delete_tag(message, state)
    GetTags(..) -> handle_get_tag(message, state)
    Nodes(..) -> handle_get_nodes_data(message, state)
    TaggedNodes(..) -> handle_get_nodes_filtered(message, state)
    MultipleUpdates(..) -> handle_internal_multiple_updates(message, state)
    InternalUpdateTag(..) -> handle_internal_update_tag(message, state)
  }
}

fn node_from_dynamic(dyn: Dynamic) {
  atom.from_dynamic(dyn)
  |> result.nil_error
  |> result.try(fn(atom) { node.connect(atom) |> result.nil_error })
}

fn handle_init(message: Message, state: State) -> actor.Next(Message, State) {
  let assert Initialize(self) = message

  process.send(self, Tick(self))

  let selector =
    process.new_selector()
    |> process.selecting(self, function.identity)
    |> process.selecting_record3(
      atom.create_from_string("node_tags_set"),
      fn(node: Dynamic, content: Dynamic) -> Message {
        let assert Ok(node) = node_from_dynamic(node)
        let assert Ok(#(key, value)) =
          dynamic.tuple2(dynamic.string, value_from_dynamic)(content)

        InternalUpdateTag(node, #(key, Some(value)))
      },
    )
    |> process.selecting_record3(
      atom.create_from_string("node_tags_delete"),
      fn(node: Dynamic, content: Dynamic) -> Message {
        let assert Ok(node) = node_from_dynamic(node)
        let assert Ok(key) = dynamic.string(content)

        InternalUpdateTag(node, #(key, None))
      },
    )
    |> process.selecting_record3(
      atom.create_from_string("node_tags_heartbeat"),
      fn(node: Dynamic, content: Dynamic) -> Message {
        let assert Ok(node) = node_from_dynamic(node)
        let assert Ok(dict) =
          dynamic.list(dynamic.tuple2(dynamic.string, value_from_dynamic))(
            content,
          )

        let messages =
          list.map(dict, fn(entry) {
            let #(key, value) = entry
            InternalUpdateTag(node, #(key, Some(value)))
          })

        MultipleUpdates(messages)
      },
    )

  actor.Continue(state, Some(selector))
}

fn handle_tick(message: Message, state: State) -> actor.Next(Message, State) {
  let assert Tick(self) = message

  process.send_after(self, 1000, Tick(self))

  let deleted_nodes =
    dict.keys(state.nodes) |> list.filter(list.contains(node.visible(), _))
  let filtered_nodes = dict.drop(state.nodes, deleted_nodes)

  let nodes_to_send =
    node.visible()
    |> list.shuffle
    |> list.take(list.length(node.visible()) / 3 + 1)

  list.each(nodes_to_send, node.send(
    _,
    state.name,
    #(
      atom.create_from_string("node_tags_heartbeat"),
      node.to_atom(node.self()),
      dict.to_list(state.tags),
    ),
  ))

  actor.continue(State(..state, nodes: filtered_nodes))
}

fn handle_set_tag(message: Message, state: State) -> actor.Next(Message, State) {
  let assert SetTag(key, value) = message

  let tags = dict.insert(state.tags, key, value)

  let msg = #(
    atom.create_from_string("node_tags_set"),
    node.to_atom(node.self()),
    #(key, value),
  )

  node.visible() |> list.each(node.send(_, state.name, msg))

  actor.continue(State(..state, tags: tags))
}

fn handle_delete_tag(
  message: Message,
  state: State,
) -> actor.Next(Message, State) {
  let assert DeleteTag(key) = message

  let tags = dict.delete(state.tags, key)

  let msg = #(
    atom.create_from_string("node_tags_delete"),
    node.to_atom(node.self()),
    key,
  )

  node.visible() |> list.each(node.send(_, state.name, msg))

  actor.continue(State(..state, tags: tags))
}

fn handle_get_tag(message: Message, state: State) -> actor.Next(Message, State) {
  todo
}

fn handle_get_nodes_data(
  message: Message,
  state: State,
) -> actor.Next(Message, State) {
  todo
}

fn handle_get_nodes_filtered(
  message: Message,
  state: State,
) -> actor.Next(Message, State) {
  todo
}

fn handle_internal_update_tag(
  message: Message,
  state: State,
) -> actor.Next(Message, State) {
  todo
}

fn handle_internal_multiple_updates(
  message: Message,
  state: State,
) -> actor.Next(Message, State) {
  todo
}
