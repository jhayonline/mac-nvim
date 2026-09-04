# Git and GitHub

Inline blame like GitLens, gutter signs with hunk staging, a full git TUI, a
proper diff/review UI, and GitHub pull requests and issues without leaving the
editor.

Everything lives under `<leader>g`, which was previously unused.

---

## The four layers

They exist because each does something the others can't:

| Layer | Scope | Use it for |
| --- | --- | --- |
| **gitsigns** | this buffer | Who wrote each line, what changed, staging individual hunks |
| **diffview** | a range of commits | Reviewing a branch, a file's history, resolving merge conflicts |
| **lazygit** | the repo | Committing, rebasing, stashing, branches, remotes |
| **octo** | GitHub | Pull requests, issues, reviews, comments |

---

## Blame — the GitLens equivalent

This is what you asked for, and it's on by default.

As your cursor moves, the last commit that touched the current line appears in
faint text at the end of it:

```
    const total = items.length;        You, 2 days ago · feat: change line two
    return <div>{total}</div>;         You, 9 days ago · init: first three lines
    const draft = true;                uncommitted
```

It says **You** when the commit author matches your `git config user.name`
(`jhayonline`), and the author's name otherwise — the same convention GitLens
uses. Uncommitted lines say so rather than showing stale information.

| Key | Action |
| --- | --- |
| `<leader>gb` | Blame popup for this line — full hash, author, date, message |
| `<leader>gB` | Blame popup **with the commit's diff**, so you see what that commit actually did |
| `<leader>gL` | Blame the **whole file** in a side pane (VS Code's "Toggle File Blame") |
| `<leader>gt` | Toggle the inline blame off/on |
| `<leader>gf` | Lazygit log **of this file** — every commit that touched it |
| `<leader>gh` | Diffview history of this file, with the diff for each commit |

`<leader>gh` in visual mode gives you the history of just the **selected
lines** — the "who changed this function and why" question, answered directly.

If the inline blame ever feels like clutter, `<leader>gt` toggles it for the
session; to turn it off permanently set `current_line_blame = false` in
`lua/engine/plugins/git.lua`.

---

## Hunks — what changed, and staging it

Change signs appear in the gutter: `▎` for added and changed lines, `▁` for
deleted ones, in distinct colours. Staged changes get their own sign, so you
can see what's already in the index.

| Key | Action |
| --- | --- |
| `]h` / `[h` | Next / previous hunk |
| `<leader>gp` | Preview the hunk inline (the old lines appear above) |
| `<leader>gP` | Preview the hunk in a floating window |
| `<leader>gs` | Stage hunk (visual mode: stage just the selected lines) |
| `<leader>gr` | Reset hunk (visual mode: reset the selected lines) |
| `<leader>gu` | Undo the last stage |
| `<leader>gS` / `<leader>gR` | Stage / reset the whole buffer |
| `<leader>gd` | Diff this file against the index |
| `<leader>gD` | Diff this file against `HEAD~` |
| `<leader>gq` | Send every hunk in the repo to the quickfix list |
| `dih` / `vih` | Delete / select "in hunk" — a text object |

Staging a visual selection is the feature to remember: it's how you split one
messy edit into two clean commits without leaving the file.

`]h` and `[h` fall through to plain `]c`/`[c` inside a diff, so the same keys
work while resolving a conflict.

---

## Lazygit — the repo

`<leader>gg` floats [lazygit](https://github.com/jesseduffield/lazygit) over the
editor, rooted at the repo of the current file. It's the fastest way to commit,
rebase interactively, manage branches, stash, cherry-pick, or fix up a commit.

| Key | Action |
| --- | --- |
| `<leader>gg` | Lazygit |
| `<leader>gl` | Lazygit log for the repo |
| `<leader>gf` | Lazygit log for the current file |

Buffers are reloaded automatically when it exits, so a rebase or checkout done
inside lazygit doesn't leave you editing a stale file.

It's launched through snacks.nvim, which passes your editor colours in, so it
matches whatever `:Theme` you're on.

---

## Diffview — reviewing changes

Gitsigns shows one buffer. Diffview shows a whole changeset, with a file panel
on the left and a real side-by-side diff on the right.

| Key | Action |
| --- | --- |
| `<leader>gv` | Working tree vs index |
| `<leader>gV` | Close diffview |
| `<leader>gm` | **This branch vs main** — review your own work before pushing |
| `<leader>gh` | History of this file (visual: of the selected lines) |
| `<leader>gH` | History of this branch |

`<leader>gm` is the one to reach for before opening a PR: it shows exactly what
your branch adds relative to `origin/HEAD`.

**Merge conflicts** open in a three-way layout — OURS | RESULT | THEIRS — with
diagnostics suppressed so the conflict markers don't produce a wall of LSP
errors. `git config merge.conflictstyle` is set to `zdiff3`, which also shows
the common ancestor in the markers so you can see what each side changed.

---

## GitHub — pull requests and issues

`gh` (the official GitHub CLI, 2.98.0) is installed and octo.nvim talks to it.

> **You don't configure your username anywhere.** octo uses whatever account
> `gh auth login` authenticated, and `gh` handles the OAuth. That's also why
> this works for any org repo you have access to, not just `jhayonline/*`.

### One step you have to do yourself

Authentication is an interactive browser flow, so run it in this session by
typing:

```
! gh auth login
```

Choose **GitHub.com** → **HTTPS** → **Login with a web browser**, and paste the
one-time code. Verify with `gh auth status`.

Then:

| Key | Action |
| --- | --- |
| `<leader>gop` | List pull requests |
| `<leader>goc` | Create a pull request |
| `<leader>goo` | Check out a pull request locally |
| `<leader>gor` | Start a review |
| `<leader>goi` | List issues |
| `<leader>gon` | New issue |
| `<leader>gos` | Search GitHub |

PRs and issues open as real buffers: edit the description and `:w` to save it
back, comment inline, approve or request changes. `:Octo` covers everything
else — `:Octo pr checks`, `:Octo pr merge`, `:Octo issue close`, and so on.

While reviewing, `<leader>gor` starts a review session where you add comments
on specific lines and submit them as one batch, the way you would on the web.

### Opening things in the browser

`<leader>gx` opens the current file on github.com at the current line, using a
permanent commit URL rather than a branch reference. It works on a visual
selection too, so it's the fastest way to send a colleague a link to exactly
the lines you're talking about.

---

## What changed outside Neovim

`git-delta` was installed and set as git's pager, which affects `git diff` and
`git show` in your terminal, and the diffs shown inside lazygit. Your previous
`~/.gitconfig` is backed up at `~/.gitconfig.bak-predelta`. The additions:

```ini
[core]
    pager = delta
[interactive]
    diffFilter = delta --color-only
[delta]
    navigate = true
    line-numbers = true
[merge]
    conflictstyle = zdiff3
[diff]
    colorMoved = default
```

To go back to plain git diffs: `git config --global --unset core.pager`.

`nvim-tree` also had `git = { enable = false }`, so the file tree never showed
which files had uncommitted work. That's now on, including on parent
directories.

---

## Where things live

```
lua/engine/plugins/git.lua        gitsigns, diffview, octo
lua/engine/plugins/snacks.lua     lazygit, gitbrowse
lua/engine/plugins/nvim-tree.lua  git status in the file tree
~/.gitconfig                      delta as pager, zdiff3 conflict style
```

Installed binaries: `gh` 2.98.0, `lazygit` 0.64.1, `delta` 0.19.2.

---

## Troubleshooting

**No inline blame.** The file has to be tracked in a git repo, and the line
committed. Check `:Gitsigns debug_messages`. `<leader>gt` toggles it.

**Blame says the wrong author.** It reads `git config user.name`; yours is
`jhayonline` / `jhaycodes999@gmail.com`.

**octo says "gh not found" or "not authenticated".** Run `! gh auth login`.

**No signs in the gutter.** `signcolumn` must not be `no` — it's `yes`
globally, but check a stray `ftplugin` if one filetype is affected.

**Lazygit opens in the wrong repo.** It roots at the current file's repo, not
the cwd. Open a file inside the repo you mean first.
