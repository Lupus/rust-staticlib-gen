val workspace_filename : string
val dune_project_filename : string

module Kind : sig
  type t =
    | Dune_workspace
    | Dune_project
end

type t =
  { dir : string
  ; to_cwd : string list
  ; reach_from_root_prefix : string
  ; kind : Kind.t
  }

val get : unit -> t
