(module repl
  {require {u gitabra.util
            st gitabra.git_status
            job gitabra.job
            outliner gitabra.outliner }})

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

(comment
  (unload)

  (st.gitabra_status)

  outliner
  outline
  (getmetatable outline)
  (setmetatable outline outliner)

  (def outline (outliner.new {}))

  outline

  (do
    (outline:add_node nil {:heading_text "first heading!"
                           :id "status header"})
    (outline:add_node nil {:heading_text "Untracked files"
                           :id "untracked"})
    (outline:add_node nil {:heading_text "Unstaged changes"
                           :id "unstaged"})
    (outline:add_node nil {:heading_text "Staged changes"
                           :id "staged"})
    (outline:add_node nil {:heading_text "Recent commits"
                           :id "recent"})
  )

  (outline:node_by_id "status header")

  (outline:close)
)
