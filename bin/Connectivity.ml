let check_cargo_connectivity () =
  let timeout = 5.0 in
  let host = "crates.io" in
  let port = 443 in
  try
    let addr_info =
      Unix.getaddrinfo host (string_of_int port) [ Unix.AI_SOCKTYPE Unix.SOCK_STREAM ]
    in
    match addr_info with
    | [] -> false
    | ai :: _ ->
      let sock = Unix.socket ai.Unix.ai_family ai.Unix.ai_socktype ai.Unix.ai_protocol in
      Unix.set_nonblock sock;
      let start_time = Unix.gettimeofday () in
      let rec connect_with_timeout () =
        try
          Unix.connect sock ai.Unix.ai_addr;
          true
        with
        | Unix.Unix_error (Unix.EINPROGRESS, _, _)
        | Unix.Unix_error (Unix.EWOULDBLOCK, _, _) ->
          let _, writable, _ = Unix.select [] [ sock ] [] timeout in
          if writable <> []
          then true
          else if Unix.gettimeofday () -. start_time > timeout
          then false
          else connect_with_timeout ()
        | _ -> false
      in
      let result = connect_with_timeout () in
      Unix.close sock;
      result
  with
  | _ -> false
;;
