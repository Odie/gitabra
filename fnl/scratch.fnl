(module scratch
  {require {u gitabra.util}})

(do
  (def r (u.system_async "git status"))
  r)

(do
  (def r (u.system_async ["git" "show" "--no-patch" "--format='%h %s'"]))
  r)

