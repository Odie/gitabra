(module repl
  {require {u gitabra.util
            st gitabra.git_status
            job gitabra.job
            outliner gitabra.outliner
            nvim aniseed.nvim
            lpeg lpeg
            patch_parser gitabra.patch_parser
            }})

(def api vim.api)

(def plugin_name "gitabra")

(defn unload
  []
  (let [dir (.. plugin_name "/")
        dot (.. plugin_name ".")]
    (each [key _ (pairs package.loaded)]
  	  (if (or (vim.startswith key dir)
              (vim.startswith key dot)
              (= key plugin_name))
         (do
    	     (tset package.loaded key nil)
  		     (print "Unloaded: " key))))))

(defn cleanup-buffer
  [buf-name]
  (let [bufnr (vim.api.nvim_eval (string.format "bufnr(\"%s\")" buf-name))]
    (when (not= bufnr -1)
      (vim.api.nvim_buf_delete bufnr {}))))

(defn clean-unnamed-buffers
  []
  (each [_ bn (pairs (vim.api.nvim_list_bufs))]
    (if (= (vim.api.nvim_buf_get_name bn) "")
      (vim.api.nvim_buf_delete bn {}))))

(comment
  (unload)

  (st.status_info)
  (do
    (api.nvim_command ":message clear")
    (cleanup-buffer "GitabraStatus")
    (st.gitabra_status))

  (st.get_sole_status_screen)

  (def sc (st.get_sole_status_screen))

  (api.nvim_buf_get_extmark_by_id sc.outline.buffer
                                  outliner.namespace_id
                                  1
                                  {})

  outliner
  outline
  (getmetatable outline)
  (setmetatable outline outliner)

  (def outline (outliner.new))

  outline

  (outline:node_by_id "status header")

  (outline:close)

  nvim

  api

  vim

  (def t (u.system_async "git diff"))
  (patch_parser.parse_patch (. t.output 1))

  (st.hunk_infos)
)
