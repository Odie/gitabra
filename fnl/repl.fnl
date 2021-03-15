(module repl
  {require {
            u gitabra.util
            st gitabra.git_status
            job gitabra.job
            outliner gitabra.outliner
            nvim aniseed.nvim
            lpeg lpeg
            zipper gitabra.zipper
            co gitabra.git_commit
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

  vim
  vim.fn
  api
)
