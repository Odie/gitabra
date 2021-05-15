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
[vim-plug](https://github.com/junegunn/vim-plug)
```
Plug 'Odie/gitabra'

lua << EOF
  require("gitabra").setup {
    -- Optional call to `setup`
    -- Leave empty to use defaults
  }
EOF

```

[Packer](https://github.com/junegunn/vim-plug)
```
use {'Odie/gitabra',
	opt = true,
  cmd = {'Gitabra'},
	config = function()
    require("gitabra").setup {
      -- Optional call to `setup`
      -- Leave empty to use defaults
    }
	end
}
```

## Configuration
Gitabra currently use the following defaults.
```
{ 
  disclosure_sign = {
    collapsed = ">",
    expanded = "⋁"
  }
}
```
Modified settings can be set via `gitabra.setup()`. This needs to be done before activating
the plugin via the `Gitabra` command the first time.

## WARNING!
This is alpha quality software!

It *shouldn't* but might discard data you did not intend to.
Be careful!
