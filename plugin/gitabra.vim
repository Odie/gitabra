if !exists('g:gitabra_status_window_pos')
  let g:gitabra_status_window_pos = 'botright vsplit'
endif

command Gitabra lua require'gitabra'.gitabra_status()
