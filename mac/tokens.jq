# Lit des transcripts Claude Code (lignes JSON brutes, jq -nR) et totalise les tokens
# par jour (heure locale du Mac) et par modèle :
#   { "2026-10-07": { "claude-opus-5-5": [entrée, sortie, cache 5 min, cache 1 h, lecture cache] } }
# Un même message apparaît sur plusieurs lignes : on ne le compte qu'une fois.
[ inputs
  | fromjson?
  | select(type == "object" and .type == "assistant" and (.message.usage? | type) == "object")
  | select((.message.model // "") != "<synthetic>")
  | {
      id: ((.message.id // .uuid // "") + ":" + (.requestId // "")),
      day: ((.timestamp // "") | sub("\\.[0-9]+"; "") | (try fromdateiso8601 catch null)
            | if . == null then null else strflocaltime("%Y-%m-%d") end),
      model: (.message.model // "inconnu"),
      u: .message.usage
    }
  | select(.day != null)
]
| unique_by(.id)
| reduce .[] as $e ({};
    ($e.u.cache_creation.ephemeral_1h_input_tokens? // 0) as $w1
    | ((($e.u.cache_creation_input_tokens // 0) - $w1) | if . < 0 then 0 else . end) as $w5
    | .[$e.day][$e.model] |= (
        (. // [0, 0, 0, 0, 0]) as $a
        | [ $a[0] + ($e.u.input_tokens // 0),
            $a[1] + ($e.u.output_tokens // 0),
            $a[2] + $w5,
            $a[3] + $w1,
            $a[4] + ($e.u.cache_read_input_tokens // 0) ]
      )
  )
