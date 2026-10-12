# git.lua — GitHub clone / pull / push for ComputerCraft 1.75 (MC 1.7.10)

A single-file Lua program that lets an in-game computer pull a GitHub repository
(usually just your Lua scripts) into its own filesystem, update it later, and push
local edits back.

It is **not** a git client: ComputerCraft 1.75 has no sockets and no websockets, so
the git wire protocol is impossible. It drives the GitHub REST API instead, which
covers the same workflow for GitHub-hosted repos. The version-specific API facts it
depends on are listed under **Limitations** below.

## Files
| path | what |
|---|---|
| `git.lua` | the program (~50 KB, fits the default 1 MB computer disk) |
| `install_CC_Git.lua` | installer/updater: puts `git` in `/usr` and on the shell path |
| `git_complete.lua` | tab completion for `git` (commands, flags, local paths) |
| `../CC-1.75-QUIRKS.md` | version quirks reference for you and other agents |
| `tests/` | offline test suite (323 assertions) — runs outside Minecraft |

## Install

**From a floppy (simplest).** Put `git.lua`, `install_CC_Git.lua` and
`git_complete.lua` on the floppy, then on the computer:

```
/disk/install_CC_Git
reboot
```

### Install location and the boot hook

`/rom` is read-only in 1.75 (it is a `JarMount` straight out of the jar), so there is no
way to install `git` the way `list` and `copy` ship. The default shell path is
`.:/rom/programs:...` and every entry in it except `.` is read-only, which leaves two
options: a folder you add yourself, or the current directory.

So the installer puts the programs in `/usr` and writes a **hook at the top of
`/startup`** — the only boot hook ComputerCraft 1.75 has. Top, not bottom: an existing
`/startup` may error out or block forever, and anything appended after it never runs.
The hook is three lines:

```lua
-- git.lua path entry (added by install_CC_Git.lua)
if not shell.path():find("/usr", 1, true) then shell.setPath(shell.path() .. ":/usr") end
if fs.exists("/usr/git_complete") then shell.run("/usr/git_complete") end
```

The marker comment and the code are on **separate lines**; a `--` marker in front of the
code comments the code out, and the hook silently does nothing.

```
install_CC_Git unhook     # remove our hook again, leaving your startup alone
```

If some **other program writes `/startup`**, our line cannot survive: that program owns
the file. `swarm_server.lua` is the example — it writes `/startup` on every run, and its
`/startup` is a `while true do shell.run("/swarm_server.lua") … sleep(3) end` loop, so the
hook is overwritten within seconds. The installer detects that shape and says so; the fix
is to put the path line in the text *that program* writes. `install_CC_Git hook` prints it:

```
if not shell.path():find("/usr", 1, true) then shell.setPath(shell.path() .. ":/usr") end
```

Once that line lives in the text your program writes, the installer notices it and
**leaves the file alone** — `your /startup already sets the path - left alone` — and
`unhook` will not remove a path line it did not add. `status` reports where the entry
is and ignores comments above it: `path entry is line 2, where it belongs`.

Re-running the installer also **migrates** the old appended block: it strips every trace
of the previous hook and writes the new one at the top, so an upgrade from an earlier
version fixes itself.

If you would rather not touch `/startup` at all, both of these work with no setup:

```
/usr/git status           # absolute path, works from anywhere
cd cc && git status       # `.` is on the path, so a program in the cwd always runs
```

One caveat: if your own startup calls `shell.setPath(...)` it replaces the path outright.
The hook is guarded against double-adding, but a plain `shell.setPath` in your script has
to include `/usr` itself.

On the floppy, keep the programs **extension-less** as well (`git`, `install_CC_Git`,
`StartHere`) — the shell matches names exactly, so `/disk/install_CC_Git` is what you
type, and that is also how the ROM ships its own programs.

It installs `git.lua` as **`/usr/git`** (no extension — ComputerCraft's shell matches
program names exactly and never appends `.lua`), the updater as `/usr/install_CC_Git`,
and the completer as `/usr/git_complete`, then writes the boot hook. After a reboot
`git` works from any directory.

**Running it again is safe, and it is the way to update.** With no arguments it
re-pulls itself, then installs or refreshes every program; files that already match are
left alone, and a failed download never removes a working copy.

```
install_CC_Git            # update everything (self-update first, then the programs)
install_CC_Git update     # same, but never use a copy sitting next to the script
install_CC_Git status     # what is installed, which version, where the hook is
```

What it prints is deliberately short. A first install:
```
install_CC_Git 1.3.0 installed
git 1.4.0 installed
git_complete installed
set up /startup to put git on the path
reboot to put git on the path, then from any folder: git help
```
An update says what moved to what, and only that:
```
install_CC_Git 1.2.0 -> 1.3.0
git 1.3.0 -> 1.4.0
reboot to put git on the path, then from any folder: git help
```
Nothing to do is one line: `git 1.4.0 - up to date`. Problems are still printed in
full - a download that failed, a disk that is full - because a quiet failure is worse
than a noisy one. `install_CC_Git status` is where the detail lives.

**It updates itself, then runs the new copy.** The installer re-pulls itself first. If
that changed anything, it writes the new copy and hands the rest of the job to it
(`shell.run /usr/install_CC_Git --reran`), so you never type the command twice and the
work is done by current code. `--reran` stops the child from doing it again, so a repo
that keeps changing cannot loop. If it cannot re-run itself, it says so
(`! could not run the new copy - finishing with the old one`) and still installs
everything, using the file list read out of the copy it just downloaded.

**A stale copy that was launched removes itself.** A stray `install_CC_Git` in the
computer root shadows `/usr` - the shell path starts with `.` - so the old copy keeps
getting run and doing old things. When that happens, the new copy does the work and the
old one is then deleted: `removed the old copy at /install_CC_Git`. Copies on a floppy
are never deleted - they are someone's offline installer - and nothing is deleted if the
new copy never got to run.

### Tab completion
`git <TAB>` completes the command words, `--<TAB>` completes the flags, and a path
argument completes files and folders from the current directory (`/usr/gi<TAB>` works
from anywhere). The completer is a separate small file, `git_complete.lua`, installed
next to `git`:

- the boot hook runs it, so completion is live on the **first** command after a reboot —
  the shell needs the completer registered before you type the command;
- `git` also registers it when it runs, so on a computer whose startup file belongs to
  another program (swarm_server) completion arrives with the first `git` command;
- up/down arrows stay ComputerCraft's own command history — a program cannot take them
  over at the prompt.

Note: `fs.complete()` is documented in `rom/help/fs` and used by ComputerCraft's own
`rom/startup`, but this jar never registers it, so the built-in file completion is
broken here. `git_complete.lua` lists and matches by hand instead.

**No floppy?** Any way of getting the text of `install_CC_Git.lua` onto the computer
works — `pastebin get`, a second computer over rednet, or writing the file into the
computer's own storage with the game closed. Once it is there, it downloads `git.lua`
and the completer itself.

## First install on an empty computer

If the computer has nothing on it yet, one pasted line gets you a downloader: see
`../StartHere/README.md` for the line and the steps.

## Working directory

`git` follows your current directory the way git on a desktop does:

```
mkdir projects
cd projects
git clone PreDawnHydra/Predawn-CC-1.7.10-Program-Repo   # -> ./Predawn-CC-1.7.10-Program-Repo
cd Predawn-CC-1.7.10-Program-Repo
git status                                               # acts on this clone
```

With no destination, `clone` uses the repository name. `pull`, `push`, `status`,
`ls` and `branch` all default to the clone in the current directory.

### Troubleshooting: git not found

```
install_CC_Git status     # says exactly where the path entry is
```

1. **You have not rebooted.** `shell.setPath` only changes the shell that calls it, so
   a program can never fix the path of the shell that launched it. One `reboot`.
2. **Another program rewrites `/startup`.** `install_CC_Git status` says
   `this /startup regenerates itself, so another program owns it` and prints the line to
   add there instead. See *Install location and the boot hook* above. Older installers appended their block to the *bottom* of
   `/startup`, where a startup script that errors out or loops forever never reaches
   it. Current `install_CC_Git` detects that and moves it to line 1 — status says
   `path entry is line 1, where it belongs` when it is right, and tells you to run the
   installer when it is not.
3. **A floppy is in the drive.** If a mounted floppy carries a `startup` file, the ROM
   startup runs *that* instead of the computer's `/startup` — the hook never executes.
4. **Your own startup calls `shell.setPath(...)`.** That replaces the path outright; add
   `/usr` to it yourself.

And with no hook at all, both of these always work: `/usr/git status`, or
`cd <clone folder>` then `git status`.

## Usage

```
git clone <owner>/<repo> [branch] [dest] [--path=PFX] [--ext=lua,md] [--max=BYTES] [--new]
git pull  [dest] [--prune] [--force]
git push  [dest] [message] [--all] [--force]
git status [dest]        git ls [dest]        git branch [dest]
git token [<pat>]        git auth [owner/repo]
git help                 git version
```

Examples:

```
git clone Equbuxu/mine master mine --ext=lua      # only .lua files
git clone you/cc-scripts main scripts --path=lib  # only lib/
cd scripts && git pull                            # update in place
git pull scripts --prune                          # also delete upstream removals
git token ghp_xxxxxxxxxxxxxxxx                    # store a token (write scope)
git push scripts "fix drill routine"              # upload local edits
```

From another program: `local git = require "git"` — then call
`git.cmdPull({"scripts"})`, `git.rawGet(...)`, `git.json.decode(...)`, etc.

Flags: `--path=` prefix filter, `--ext=a,b` extension filter, `--prune` delete
files removed upstream, `--max=` refuse a download larger than N bytes,
`--force` re-download everything, `--all` push every local file, `--token=` use a
token for one command, `--new` allow cloning a folder that does not exist yet.

## Cloning and tracking individual directories

**A `--path` clone is flat by default.** `--path=MineSwarm/Swarm_Server/` creates a
folder called `Swarm_Server` and puts the files straight inside it — the folder you asked
for is the folder you get, with no repository folders repeated above it:

```
git clone PreDawnHydra/Predawn-CC-1.7.10-Program-Repo --path=MineSwarm/Swarm_Server/
cd Swarm_Server
ls          # swarm  swarm_server.lua
```

Desktop git does **not** do this: a clone always contains the repo root, and sparse
checkout hides paths without moving a subtree up. This is a deliberate deviation for
in-game use, and `--keep-path` gets git's layout back:

```
git clone you/repo --path=MineSwarm/Swarm_Server/ --keep-path   # -> repo/MineSwarm/Swarm_Server/...
```

`--path` works with or without a trailing slash — `--path=MineSwarm/Swarm_Server` and
`--path=MineSwarm/Swarm_Server/` mean the same thing, and a clone made before that was
fixed repairs its own `.gitcfg` the next time you pull or push.

The prefix is saved in `.gitcfg`, so `pull` and `push` translate local names back to
repository names — a flat clone pushes `swarm_server.lua` to
`MineSwarm/Swarm_Server/swarm_server.lua`. Clones made before this change keep their
nested layout; the flag lives in their `.gitcfg`.

`--path=` is stored in `.gitcfg`, so `pull` and `push` keep honouring it — you never
have to carry the whole repo on the computer.

```
git clone PreDawnHydra/Predawn-CC-1.7.10-Program-Repo main cc_git --path=CC_git/
git pull cc_git --prune
git push cc_git "tweak git.lua"
```

Only `CC_git/` is fetched, and `push` uploads only files under `CC_git/` — the tree
is built on top of the current one (`base_tree`), so every other folder in the repo
is left exactly as it is. Keep the trailing slash: `--path=CC_git/` matches the
folder, while `--path=CC_git` would also match `CC_git_old/`.

To start a program folder that does not exist upstream yet:

```
git clone PreDawnHydra/Predawn-CC-1.7.10-Program-Repo main cc_new --path=MyProg/ --new
mkdir MyProg            # inside cc_new/
edit MyProg/turtle.lua
git push cc_new "add MyProg"
```

The `--new` clone checks out nothing but the branch head, so the push creates the
folder. Without `--new` a filter that matches nothing is refused as a typo.

One clone per program is the normal shape: `cc_git`, `cc_swarm`, each with its own
`.gitcfg` and its own `--path`.

## Setting up push

1. **Make a token.** GitHub → Settings → Developer settings → Personal access
   tokens → **Fine-grained token**:
   - Repository access: *Only select repositories* → your repo
   - Permissions → Repository permissions → **Contents: Read and write**
     (that single permission covers `git/blobs`, `git/trees`, `git/commits`,
     `git/refs` and `merges` — confirmed against GitHub's permissions docs)
   - Pick an expiry you're comfortable with. A classic token with the `repo`
     scope also works.
2. **Store it in-game**, from the computer's home directory:
   ```
   git token ghp_xxxxxxxxxxxxxxxx
   git token            # confirm it is stored
   ```
   It is written to `.git-token`; lookups walk up parent directories, so one
   token at the computer root works from any clone directory. `--token=ghp_...`
   overrides it for a single command.
3. **Push:**
   ```
   git push cc "updated drill routine"
   git push cc "first upload" --all     # also upload files never in the repo
   ```

Push safety notes:
- The token sits in **plaintext** inside your world save. Use a repo-scoped
  fine-grained token, not an account-wide one, and expire it.
- Change detection is size + a 31-bit content checksum, so same-length edits are
  caught. Files are uploaded exactly as `readAll()` hands them over, so a pushed
  file loses its final newline.
- If the repo protects `main`, the merge step fails and git.lua tells you which
  `cc-sync/<sha>` branch holds the commit — merge it on GitHub.

### Push pre-flight check

Before uploading a single byte, `push` compares the commit in `.gitcfg` with the current
branch head. If they differ, it lists what changed upstream and whether it clashes with
your edits:

```
main has moved on since you pulled (you are at 308f308, it is at c94b5ea)
  you changed 2 file(s); 3 changed on GitHub since then
  upstream: init.lua
  upstream: lib/core.lua (deleted upstream)
  BOTH changed - a pull would replace your copy: init.lua
push refused: 1 file(s) changed on both sides. Save them, run 'git pull', re-apply,
then push (or use --force)
```

Nothing was uploaded, so no `cc-sync` branch is left behind by a doomed push. If the two
sides don't overlap you get `no overlap with your changes - 'git pull' is safe, and this
push will merge cleanly` and the push goes ahead. `--force` sends it regardless.

## Commands

- **clone** — resolves the branch head (`/git/ref/heads/<branch>`; falls back to
  the repo's default branch if your branch does not exist), reads the recursive
  tree, refuses to start if the download would not fit on disk, then fetches each
  file from `raw.githubusercontent.com` pinned to that commit sha. Writes a
  `.gitcfg` manifest (owner, repo, branch, commit, tree, per-file sha + size).
- **pull** — re-resolves the branch head, diffs blob shas against `.gitcfg`,
  re-downloads only changed/new files, reports upstream removals (deletes them
  only with `--prune`). `--prune` deliberately skips the "already up to date"
  shortcut, so it can clear leftovers even when your commit already matches the
  branch head.
- **status** — compares each tracked file's size *and* content fingerprint with the
  manifest: `modified`, `new`, `missing`, or `clean`.
- **push** — needs a token with write access. Uploads changed/new files as blobs
  (base64), builds a tree on top of the cloned tree, makes a commit parented on
  your known commit, creates a throwaway branch `cc-sync/<sha>`, then asks GitHub
  to merge it into your branch server-side (`POST /merges`). All of that is POST,
  which is what CC 1.75 can send.

If `git status` lists files as modified that you never touched, your `.gitcfg` was
written by an older build of `git.lua` (it stored less per-file information).
Update the program, then refresh the manifest:

```
git pull cc --force
```

## Limitations

- **Disk is capped per computer** — ComputerCraft's `computerSpaceLimit` defaults to
  1 MB. `clone` and `pull` pre-check the download size and refuse rather than fill it.
- **HTTP is text-only** in 1.75: responses are decoded to a Java String, so binary
  files (images, jars) come out corrupted. Lua/text files are fine.
- `readAll()` drops the trailing newline and turns CRLF into LF. clone/pull
  restore the trailing newline using the blob size from the tree API, but a CRLF
  file is written back as LF.
- **Non-2xx responses look identical to network failures** (`http.get` returns
  `nil`), so a 404, a rate limit, and an offline computer all report the same
  error. Unauthenticated API use is capped at 60 requests/hour — clone/pull use
  only 2 API calls each, so you are fine unless you push a lot.
- **push cannot update a ref directly** (no PATCH/DELETE in 1.75): it merges a
  throwaway branch instead, and leaves that branch behind on GitHub.
- **push cannot delete or rename a file** — the tree is built on top of the current
  one, and ComputerCraft 1.75 has no `DELETE` or `PATCH`. Deleting or renaming needs a
  real git client on a PC. That also means a file and a folder cannot be swapped for
  each other in-game (git rejects the name collision).
- **push never uploads `.git-token` or `.gitcfg`**, at any depth — so cloning into
  the computer's root directory (where the token lives) cannot publish your token
  to GitHub.
- Big repos: the recursive tree call can be truncated (`truncated: true`) — use
  `--path=` to clone a subdirectory. Parsing a 570 KB tree JSON takes a couple of
  seconds of CPU in-game.

## Tests

```bash
cd tests               # in the CC_git folder of this repo
npm i fengari          # the Lua interpreter the suite runs on
node run.js            # -> 323 passed, 0 failed
```

The suite emulates the CC 1.75 API (including `readAll()` newline behaviour and
nil-on-4xx) and includes real GitHub payloads captured with curl for
`Equbuxu/mine`, so clone output is checked byte-for-byte against the real files.
