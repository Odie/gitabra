	command Gitabra lua require'gitabra'.gitabra_status()

	augroup GitabraStatusFold
		au!
		" autocmd BufEnter GitabraStatus if (&filetype == "GitabraStatus") |
		" 			" -- save current fold method and expr
		" 			\ let b:foldmethod=&foldmethod |
		" 			\ let b:foldexpr=&foldexpr |
    "
		" 			" -- Let gitabra figure out the fold level
		" 			\ let &foldmethod="expr" |
		" 			" \ let &foldexpr=luaeval(printf('require"nvim-treesitter.fold".get_fold_indic(%d)', v:lnum)) |
		" 			\ let &foldexpr=gitabra#foldexpr() |
		" 			\ endif
    "
		" autocmd BufLeave GitabraStatus if (&filetype == "GitabraStatus") |
		" 			" Restore the previous fold method and expr
		" 			\ let &foldmethod=b:foldmethod |
		" 			\ let &foldexpr=b:foldexpr |
		" 			\ endif
	augroup end
