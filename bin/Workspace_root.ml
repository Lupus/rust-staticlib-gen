(*
   This module is heavily based on Workspace_root from Dune sources:
   https://github.com/ocaml/dune/blob/17071ec30d10390badcb6cb1f6a43984b1be54a6/bin/workspace_root.ml

   The MIT License

   Copyright (c) 2016 Jane Street Group, LLC opensource@janestreet.com

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE.
*)

module String_set = Set.Make (String)

let workspace_filename = "dune-workspace"
let dune_project_filename = "dune-project"

module Kind = struct
  type t =
    | Dune_workspace
    | Dune_project

  let priority = function
    | Dune_workspace -> 1
    | Dune_project -> 2
  ;;

  let lowest_priority = max_int

  let of_dir_contents files =
    if String_set.mem workspace_filename files
    then Some Dune_workspace
    else if String_set.mem dune_project_filename files
    then Some Dune_project
    else None
  ;;
end

type t =
  { dir : string
  ; to_cwd : string list
  ; reach_from_root_prefix : string
  ; kind : Kind.t
  }

module Candidate = struct
  type t =
    { dir : string
    ; to_cwd : string list
    ; kind : Kind.t
    }
end

let find () =
  let cwd = Sys.getcwd () in
  let rec loop counter ~(candidate : Candidate.t option) ~to_cwd dir : Candidate.t option =
    match Sys.readdir dir with
    | exception Sys_error msg ->
      Printf.fprintf
        stderr
        "Unable to read directory %s. Will not look for root in parent directories."
        dir;
      Printf.fprintf stderr "Reason: %s" msg;
      candidate
    | files ->
      let files = String_set.of_list (Array.to_list files) in
      let candidate =
        let candidate_priority =
          match candidate with
          | Some c -> Kind.priority c.kind
          | None -> Kind.lowest_priority
        in
        match Kind.of_dir_contents files with
        | Some kind when Kind.priority kind <= candidate_priority ->
          Some { Candidate.kind; dir; to_cwd }
        | _ -> candidate
      in
      cont counter ~candidate dir ~to_cwd
  and cont counter ~candidate ~to_cwd dir =
    if counter > String.length cwd
    then candidate
    else (
      let parent = Filename.dirname dir in
      if parent = dir
      then candidate
      else (
        let base = Filename.basename dir in
        loop (counter + 1) parent ~candidate ~to_cwd:(base :: to_cwd)))
  in
  loop 0 ~to_cwd:[] cwd ~candidate:None
;;

let get () =
  match find () with
  | Some { Candidate.dir; to_cwd; kind } ->
    { kind
    ; dir
    ; to_cwd
    ; reach_from_root_prefix = String.concat "" (List.map (Printf.sprintf "%s/") to_cwd)
    }
  | None ->
    Printf.fprintf stderr "Cannot find the root of the current workspace/project!";
    exit 1
;;
