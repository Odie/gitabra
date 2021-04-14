"" > Unicode: U+003E, UTF-8: 3E
if !exists('g:gitabra_outline_collapsed_text')
  let g:gitabra_outline_collapsed_text = '>'
endif

"" ⋁ Unicode U+22C1, UTF-8: E2 8B 81
if !exists('g:gitabra_outline_expanded_text')
  let g:gitabra_outline_expanded_text = '⋁'
endif

command Gitabra lua require'gitabra'.gitabra_status()
