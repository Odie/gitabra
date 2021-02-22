function! gitabra#foldexpr() abort
	return luaeval(printf('require"gitabra.git_status".get_fold_level(%d)', v:lnum))
endfunction

function! gitabra#foldtext() abort
	return luaeval(printf('require"gitabra.git_status".get_fold_text()'))
endfunction
