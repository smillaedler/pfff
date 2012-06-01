 * Copyright (C) 2010-2012 Facebook
(* this may loop forever ... better to realpath +> split "/" and then
 * process I think. Also dangerous. I think it would be good
 * also when walking the parents to check if there is a .svn or .hg
 * and whatever and then raise an exception
 * 
 * let parent_path_with_dotgit_opt subdir = 
 * let subdir = Common.relative_to_absolute subdir in
 * let rec aux subdir =
 * if Sys.file_exists (Filename.concat subdir "/.git")
 * then Some subdir
 * else 
 * let parent = Common.dirname subdir in
 * if parent = "/"
 * then None
 * else aux parent
 * in
 * aux subdir
 * 
 * let parent_path_with_dotgit a = 
 * Common.some (parent_path_with_dotgit_opt a)
 * 
 * todo: walking of the parent (subject to GIT_CEILING_DIRS)
 *)
let is_git_repository basedir =
  Version_control.detect_vcs_source_tree basedir =*= Some (Version_control.Git)

let find_root_from_absolute_path file =
  let xs = Common.split "/" (Common.dirname file) in
  let xxs = Common.inits xs in
  xxs +> List.rev +> Common.find_some (fun xs ->
    let dir = "/" ^ Common.join "/" xs in
    let gitdir = Filename.concat dir ".git" in
    if Sys.file_exists gitdir
    then Some dir
    else None
  )
let clean_git_patch xs =
  if (ret <> 0) 
  then failwith ("pb with command: " ^ s)
  commits +> Common_extra.progress (fun k -> Common.filter (fun (id, x) ->
    k ();
    let (Lib_vcs.VersionId scommit) = id in
    let cmd = (spf "cd %s; git show --oneline --no-color --stat %s"
                  basedir scommit) in
    let xs = Common.cmd_to_list cmd in
    (* basic heuristic: more than N files in a diff => refactoring diff *)
    List.length xs > threshold
  ))