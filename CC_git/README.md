# git.lua — GitHub clone / pull / push for ComputerCraft 1.75 (MC 1.7.10)

A single-file Lua program that lets an in-game computer pull a GitHub repository
(usually just your Lua scripts) into its own filesystem, update it later, and push
local edits back.

It is **not** a git client: ComputerCraft 1.75 has no sockets and no websockets, so
the git wire protocol is impossible. It drives the GitHub REST API instead, which
covers the same workflow for GitHub-hosted repos. See `CC-1.75-QUIRKS.md` for the
API facts this was built against.

## Files
| path | what |
|---|---|
| `git.lua` | the program (~42 KB, fits the 1 MB computer HDD) |
| `install_CC_Git.lua` | installer/updater: puts `git` in `/usr` and on the shell path |
| `../CC-1.75-QUIRKS.md` | version quirks reference for you and other agents |
| `tests/` | offline test suite (205 assertions) — runs outside Minecraft |

## Install

**From a floppy (simplest).** Put `git.lua` and `install_CC_Git.lua` on the floppy,
then on the computer:

```
/disk/install_CC_Git
reboot
```

That copies `git.lua` into `/usr` and appends a path entry to `/startup`, which
ComputerCraft runs at boot — after that `git` works from any directory. The
installer prefers the copy sitting next to it and falls back to GitHub.

**Already installed? Update in place:**

```
install_CC_Git update     # re-download git.lua from GitHub
install_CC_Git status     # what is installed, which version, is the path entry set
```

**No floppy?** Any way of getting the text of `install_CC_Git.lua` onto the
computer works — `pastebin get`, a second computer over rednet, or straight into
the save data with the game closed. Once it is there, it fetches `git.lua` itself:

```bash
cp cc-dev/CC_git/install_CC_Git.lua ".../saves/LUA_Testing/computer/8/install_CC_Git.lua"
```

## Start from nothing

If the computer has nothing on it yet, paste one line to get a downloader: see
`../StartHere/README.md` for the line and the cold-start steps.

## Where it works from

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

## Usage

```
git clone <owner>/<repo> [branch] [dest] [--path=PFX] [--ext=lua,md] [--max=BYTES] [--new]
git pull  [dest] [--prune] [--force]
git push  [dest] [message] [--all]
git status [dest]        git ls [dest]        git branch [dest]
git token [<pat>]        git help
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

## One program at a time

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

## What each command does

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

## Limits you should know

- **1 MB total disk** per computer (`computerSpaceLimit=1000000` in
  `ComputerCraft.cfg`). clone/pull pre-check the size and refuse.
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
  one. Deleting anything needs a PC: `cc-dev/publish.sh "message"` pushes from a
  real git clone. That also means a file and a folder cannot be swapped for each
  other from in-game (git rejects the name collision).
- **push never uploads `.git-token` or `.gitcfg`**, at any depth — so cloning into
  the computer's root directory (where the token lives) cannot publish your token
  to GitHub.
- Big repos: the recursive tree call can be truncated (`truncated: true`) — use
  `--path=` to clone a subdirectory. Parsing a 570 KB tree JSON takes a couple of
  seconds of CPU in-game.

## Tests

```bash
cd cc-dev/CC_git/tests
npm i fengari          # if /tmp/node_modules/fengari is missing
node run.js            # -> 205 passed, 0 failed
```

The suite emulates the CC 1.75 API (including `readAll()` newline behaviour and
nil-on-4xx) and includes real GitHub payloads captured with curl for
`Equbuxu/mine`, so clone output is checked byte-for-byte against the real files.
