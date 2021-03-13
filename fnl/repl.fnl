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

  (st.status_info)
  (do
    (api.nvim_command ":message clear")
    (cleanup-buffer "GitabraStatus")
    (st.gitabra_status)
    )

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

  ;; Excercises the `next` function of the zipper api
  (let [root {:id :root
              :children [{:id :c1
                          :children [{:id :c1-c1}
                                     {:id :c1-c2}
                                     {:id :c1-c3}]}
                         {:id :c2
                          :children [{:id :c2-c1}
                                     {:id :c2-c2}
                                     {:id :c2-c3}]}
                         {:id :c3
                          :children [{:id :c3-c1}
                                     {:id :c3-c2}
                                     {:id :c3-c3}]}]}
        z (zipper.new root :children)
        cur_path (fn [z]
                     (let [r {}]
                       (each [_ node (ipairs z.path)]
                         (u.table_push r node.id))
                       r))]
    (while (not (z:at_end))
      (z:next)
      (print (vim.inspect (cur_path z))))

    (print "is at end?" (z:at_end))
    (z:remove_end_marker)
    z)

  ;; Excercises the `next` in such a way as to prune certain branches from
  ;; a basic depth first traversal
  (let [root {:id :root
              :children [{:id :c1
                          :children [{:id :c1-c1}
                                     {:id :c1-c2}
                                     {:id :c1-c3}]}
                         {:id :c2
                          :do-not-visit true
                          :children [{:id :c2-c1}
                                     {:id :c2-c2}
                                     {:id :c2-c3}]}
                         {:id :c3
                          :children [{:id :c3-c1}
                                     {:id :c3-c2}
                                     {:id :c3-c3}]}]}
        z (zipper.new root :children)
        cur_path (fn [z]
                     (let [r {}]
                       (each [_ node (ipairs z.path)]
                         (u.table_push r node.id))
                       r))]
    (while (not (z:at_end))
      (let [node (z:node)]
        (if (. node :do-not-visit)
          (do
            (z:right)
            (print "skipping node:" (. node :id)))
          (do
            (print (vim.inspect (cur_path z)))
            (tset node :visited true)
            (z:next)))))

    (print "is at end?" (z:at_end))
    (z:remove_end_marker)
    z)

  (let [root {:id :root
              :children [{:id :c1
                          :children [{:id :c1-c1}
                                     {:id :c1-c2}
                                     {:id :c1-c3}]}
                         {:id :c2
                          :do-not-visit true
                          :children [{:id :c2-c1}
                                     {:id :c2-c2}
                                     {:id :c2-c3}]}
                         {:id :c3
                          :children [{:id :c3-c1}
                                     {:id :c3-c2}
                                     {:id :c3-c3}]}]}
        z (zipper.new root :children)
        cur_path (fn [z]
                     (let [r {}]
                       (each [_ node (ipairs z.path)]
                         (u.table_push r node.id))
                       r))]
    (z:down)


    (print "is at end?" (z:at_end))
    (z:remove_end_marker)
    ; (cur_path z)
    (z:parent_node)
    )


  (let [root (u.get_in (st.get_sole_status_screen) [:outline :root])
        z (zipper.new root "children")
        cur_path (fn [z]
                     (let [r {}]
                       (each [_ node (ipairs z.path)]
                         (u.table_push r (or node.id node.text)))
                       r))]

    (while (not (z:at_end))
      (print (vim.inspect (cur_path z)))
      (z:next)
      )

    (print "is at end?" (z:at_end))
    (z:remove_end_marker)
    ; (cur_path z)
    ; z
    )

  (let [outline (u.get_in (st.get_sole_status_screen) [:outline])
        z (zipper.new outline.root "children")
        ]
    ; (outline:node_zipper_at_lineno 0)
    (z:down)
    z
    )

  (let [outline (u.get_in (st.get_sole_status_screen) [:outline])
        start (u.nanotime)
        z (outline:node_zipper_at_lineno 9)
        stop (u.nanotime)
        ]
    (if z
      (do
        (print (string.format "elapsed [%f]" (- stop start)))
        (z:node))
      (print "node_zipper_at_lineno returned nil!")
      )
    )

  (let [outline (u.get_in (st.get_sole_status_screen) [:outline])
        node (u.get_in outline [:root :children 2])
        ]
    (tset node :collapsed true)
    node
    (outline:refresh)
    )

  (let [outline (u.get_in (st.get_sole_status_screen) [:outline])
        z (zipper.new outline.root "children") ]

    (z:next)
    (z:next)
    (z:next)
    (z:next)
    (z:children)
    )

  (st.get_sole_status_screen)

  (let [outline (u.get_in (st.get_sole_status_screen) [:outline])
        start (u.nanotime)
        _ (outline:refresh)
        stop (u.nanotime)]
    (print (string.format "Refresh took [%f]" (- stop start)))
    )

  (co.make_editor_script)
  (def j (u.system_async
           (u.interp "GIT_EDITOR=${editor_script} git commit"
                     {:editor_script (co.make_editor_script)})))

  (def j (u.system_async ["sh" "-c" "echo $GIT_EDITOR"]
                         {:env [(string.format "GIT_EDITOR=%s" (co.make_editor_script))]}))

  (def j (u.system_async ["echo" "$GIT_EDITOR"]
                         {:env [(string.format "GIT_EDITOR=%s" (co.make_editor_script))]}))
  j
  (def j (co.gitabra_commit))

  api
  vim.fn
  (vim.fn.getcwd)
  (def j (u.git_root_dir))
  (u.git_dot_git_dir)
  (u.git_root_dir)
  (u.git_dot_git_dir)

  (u.nvim_create_augroups {:ReleaseGitcommit ["BufWritePost <buffer> lua require()"
                                              "BufDelete <buffer> lua require()" ]})
  (co.test)

  (u.remove_trailing_newlines "hello world\n\n")

  (u.table_key_diff
    (u.table_array_to_set [{:id "node-1" :hello :world}
                           {:id "node-2" :hello :there}
                           ]
                          (fn [x]
                            (. x :id)))
    (u.table_array_to_set [{:id "node-1" :hello :world}
                           {:id "node-3" :hello :universe}
                           ]
                          (fn [x]
                            (. x :id))))

  (let [lm (require "gitabra.list")
        l (lm.new)]
    (print "1 empty?" (l:is_empty))
    (l:push_right :hello)
    (l:push_right :world)
    (print "2 empty?" (l:is_empty))
    (l:pop_left)
    (l:pop_left)
    (print "3 empty?" (l:is_empty))
    l
    )

  (let [md5 (require "gitabra.md5")
        start (u.nanotime)
        checksum (md5.sumhexa "hello\n")
        stop (u.nanotime)
        ]
    (print "elapsed:" (- stop start))
    checksum

    )

  (st.reconcile_status_state {:outline (outliner.new {:root {:children [{:text ["hello" "world"]
                                                                         :hello :world
                                                                         :children [{:text ["Traveler"]
                                                                                     :name "Odie"}
                                                                                    {:text ["Planes"]
                                                                                     :count 5}
                                                                                    {:text ["Trains"]
                                                                                     :arrival :on-time}]}
                                                                        {:text ["hello" "there"]
                                                                         :hello :there}]}})}

                             {:outline (outliner.new {:root {:children [{:text ["pretty" "good"]}
                                                                        {:text ["hello" "world"]
                                                                         :children [{:text ["Traveler"]}
                                                                                    {:text ["UFOs"]}
                                                                                    {:text ["Planes"]}
                                                                                    {:text ["Greys"]}]}
                                                                        {:text ["what's" "up"]}]} })}
                             )
)
