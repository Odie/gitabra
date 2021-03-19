# Gitabra

Magit-lite for neovim

## tldr
`:Gitabra` to bring up the or refresh the status buffer

While in the status buffer:

- `<tab>` to expand/collapse the node under the cursor
- `<enter>` to go to the line or file under the cursor
- `s` to stage or unstage hunk or file under the cursor (partial hunk
  supported)
- `x` to discard the hunk under the cursor (partial hunk supported)
- `q` to quit the buffer and close the window
- `cc` to start editing the commit message

While editing the commit message:

Gitabra will pass on the contents of COMMIT_EDITMSG to git when the buffer is
written to, or when the window is closed. Feel free to use ":w", ":wq", ":q",
or your favorite vim command.
