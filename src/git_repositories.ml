open Lwt.Infix
open Current.Syntax

let ( >>!= ) x f =
  x >>= function
  | Ok y -> f y
  | Error _ as e -> Lwt.return e

module Repositories = struct
  type t = No_context

  let id = "git-repositories"

  module Key = struct
    type repo = string

    type t = {
      opam_repository_master : repo;
      opam_repository_mingw_sunset : repo;
      opam_overlays : repo;
      opam_2_0 : repo;
      opam_2_1 : repo;
      opam_master : repo;
    }

    let digest {opam_repository_master; opam_repository_mingw_sunset; opam_overlays; opam_2_0; opam_2_1; opam_master} =
      let json = `Assoc [
        "opam-repository__master", `String opam_repository_master;
        "opam-repository-mingw__sunset", `String opam_repository_mingw_sunset;
        "opam-repository-mingw__overlay", `String opam_overlays;
        "opam__2.0", `String opam_2_0;
        "opam__2.1", `String opam_2_1;
        "opam__master", `String opam_master;
      ] in
      Yojson.Safe.to_string json
  end

  module Value = struct
    type hash = string [@@deriving yojson]

    type t = {
      opam_repository_master : hash;
      opam_repository_mingw_sunset : hash;
      opam_overlays : hash;
      opam_2_0 : hash;
      opam_2_1 : hash;
      opam_master : hash;
    } [@@deriving yojson]

    let marshal t = to_yojson t |> Yojson.Safe.to_string

    let unmarshal s =
      match Yojson.Safe.from_string s |> of_yojson with
      | Ppx_deriving_yojson_runtime.Result.Ok x -> x
      | Ppx_deriving_yojson_runtime.Result.Error _ -> failwith "failed to parse Git_repositories.Repositories.Value.t"
  end

  let get_commit_hash ~job ~repo ~branch =
    Current.Process.with_tmpdir ~prefix:"git-checkout" @@ fun cwd ->
    Current.Process.exec ~cwd ~cancellable:true ~job ("", [|"git"; "clone"; "-b"; branch; repo; "."|]) >>!= fun () ->
    Current.Process.check_output ~cwd ~cancellable:true ~job ("", [|"git"; "rev-parse"; "HEAD"|]) >>!= fun hash ->
    Lwt.return (Ok (String.trim hash))

  let build No_context job {Key.opam_repository_master; opam_repository_mingw_sunset; opam_overlays; opam_2_0; opam_2_1; opam_master} =
    Current.Job.start job ~level:Current.Level.Mostly_harmless >>= fun () ->
    get_commit_hash ~job ~repo:opam_repository_master ~branch:"master" >>!= fun opam_repository_master ->
    get_commit_hash ~job ~repo:opam_repository_mingw_sunset ~branch:"sunset" >>!= fun opam_repository_mingw_sunset ->
    get_commit_hash ~job ~repo:opam_overlays ~branch:"overlay" >>!= fun opam_overlays ->
    get_commit_hash ~job ~repo:opam_2_0 ~branch:"2.0" >>!= fun opam_2_0 ->
    get_commit_hash ~job ~repo:opam_2_1 ~branch:"2.1" >>!= fun opam_2_1 ->
    get_commit_hash ~job ~repo:opam_master ~branch:"master" >>!= fun opam_master ->
    Lwt.return (Ok {Value.opam_repository_master; opam_repository_mingw_sunset; opam_overlays; opam_2_0; opam_2_1; opam_master})

  let pp f _ = Fmt.string f "Git repositories"

  let auto_cancel = true
end

module Cache = Current_cache.Make(Repositories)

type t = {
  opam_repository_master : Current_git.Commit_id.t;
  opam_repository_mingw_sunset : Current_git.Commit_id.t;
  opam_overlays : Current_git.Commit_id.t;
  opam_2_0 : Current_git.Commit_id.t;
  opam_2_1 : Current_git.Commit_id.t;
  opam_master : Current_git.Commit_id.t;
}

let get ~schedule =
  let key = {
    Repositories.Key.
    opam_repository_master = "https://github.com/ocaml/opam-repository";
    opam_repository_mingw_sunset = "https://github.com/ocaml-opam/opam-repository-mingw";
    opam_overlays = "https://github.com/ocurrent/opam-repository-mingw";
    opam_2_0 = "https://github.com/ocaml/opam";
    opam_2_1 = "https://github.com/ocaml/opam";
    opam_master = "https://github.com/ocaml/opam";
  } in
  let+ {Repositories.Value.opam_repository_master; opam_repository_mingw_sunset; opam_overlays; opam_2_0; opam_2_1; opam_master} =
    Current.component "Git-repositories" |>
    let> key = Current.return key in
    Cache.get ~schedule Repositories.No_context key
  in
  {
    opam_repository_master =
      Current_git.Commit_id.v ~repo:key.opam_repository_master ~gref:"master" ~hash:opam_repository_master;
    opam_repository_mingw_sunset =
      Current_git.Commit_id.v ~repo:key.opam_repository_mingw_sunset ~gref:"sunset" ~hash:opam_repository_mingw_sunset;
    opam_overlays =
      Current_git.Commit_id.v ~repo:key.opam_overlays ~gref:"overlay" ~hash:opam_overlays;
    opam_2_0 =
      Current_git.Commit_id.v ~repo:key.opam_2_0 ~gref:"2.0" ~hash:opam_2_0;
    opam_2_1 =
      Current_git.Commit_id.v ~repo:key.opam_2_1 ~gref:"2.1" ~hash:opam_2_1;
    opam_master =
      Current_git.Commit_id.v ~repo:key.opam_master ~gref:"master" ~hash:opam_master;
  }
