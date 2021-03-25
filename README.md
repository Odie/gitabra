# Gitabra

A little Magit in neovim

![Demo Animation](../assets/gitabra-general-demo.gif?raw=true)

## Quick Start
`:Gitabra` to bring up the or refresh the status buffer

While in the status buffer:

- `<tab>` to expand/collapse the node under the cursor
- `<enter>` to visit the thing under the cursor
- `s` to stage hunk or file under the cursor (partial hunk supported)
- `S` stage all
- `u` to unstage hunk or file under the cursor (partial hunk supported)
- `U` unstage all
- `x` to discard the hunk under the cursor (partial hunk supported)
- `q` to quit the buffer and close the window
- `cc` to start editing the commit message
- `ca` to start editing the last commit message

While editing the commit message:

Gitabra will pass on the contents of COMMIT_EDITMSG to git when the buffer is
written to, or when the window is closed. Feel free to use ":w", ":wq", ":q",
or your favorite vim command.

## Installation
Using [vim-plug](https://github.com/junegunn/vim-plug)
```
Plug 'Odie/gitabra'
```

It should work fine with your favorite plugin manager.

## WARNING!
This is alpha quality software!

It *shouldn't* but might discard data you did not intend to.
Be careful!
