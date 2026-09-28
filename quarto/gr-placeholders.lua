-- Fills {placeholder} names in report text with values computed by the build
-- (reports/<id>/_snapshot/values.json, named in the document metadata as gr-values-file).
-- Only names are looked up; nothing is evaluated. Scope: text inside a block (a div with
-- gr-block, a heading with id blk-<id>, or a figure/table fig-<id>/tbl-<id>) sees that
-- block's values first, then report-wide values; all other text sees report values.

local values = {}

local function dirname(path)
  return path:match("^(.*)[/\\]") or "."
end

local function load_values(meta)
  local rel = meta["gr-values-file"]
  if not rel then return end
  rel = pandoc.utils.stringify(rel)
  local input = PANDOC_STATE.input_files[1]
  local candidates = { rel }
  if input then table.insert(candidates, 1, dirname(input) .. "/" .. rel) end
  for _, path in ipairs(candidates) do
    local f = io.open(path, "r")
    if f then
      values = pandoc.json.decode(f:read("a"))
      f:close()
      return
    end
  end
  io.stderr:write("gr-placeholders: values file not found: " .. rel .. "\n")
end

local function lookup(name, scope)
  local v = nil
  if scope and values[scope] then v = values[scope][name] end
  if v == nil and values["report"] then v = values["report"][name] end
  if v == nil or v == pandoc.json.null then return nil end
  return tostring(v)
end

local function fill(text, scope)
  return (text:gsub("{([%w_%.%-]+)}", function(name)
    local v = lookup(name, scope)
    if v == nil then
      io.stderr:write("gr-placeholders: unknown placeholder {" .. name .. "}\n")
      return nil
    end
    return v
  end))
end

local function scoped(scope)
  return {
    Str = function(el) return pandoc.Str(fill(el.text, scope)) end,
    Image = function(el)
      for k, v in pairs(el.attributes) do el.attributes[k] = fill(v, scope) end
      return el
    end
  }
end

local function block_scope(el)
  local b = el.attributes and el.attributes["gr-block"]
  if b then return b end
  local id = el.identifier or ""
  return id:match("^blk%-(.+)$") or id:match("^fig%-(.+)$") or id:match("^tbl%-(.+)$")
end

return {
  { Meta = function(meta) load_values(meta); return meta end },
  {
    traverse = "topdown",
    Div = function(el)
      local scope = block_scope(el)
      if scope then return pandoc.walk_block(el, scoped(scope)), false end
    end,
    Figure = function(el)
      local scope = block_scope(el)
      if scope then return pandoc.walk_block(el, scoped(scope)), false end
    end,
    Header = function(el)
      local scope = block_scope(el)
      if scope then return pandoc.walk_block(el, scoped(scope)), false end
    end,
    -- knitr figures arrive as an image carrying the fig-<id> label, caption and fig-alt.
    Image = function(el)
      local scope = block_scope(el)
      if scope then
        for k, v in pairs(el.attributes) do el.attributes[k] = fill(v, scope) end
        el.caption = pandoc.walk_inline(pandoc.Span(el.caption), scoped(scope)).content
        return el, false
      end
    end
  },
  -- Everything else, including the title and subtitle in the metadata, uses report values.
  {
    Str = function(el) return pandoc.Str(fill(el.text, "report")) end,
    Image = function(el)
      for k, v in pairs(el.attributes) do el.attributes[k] = fill(v, "report") end
      return el
    end
  }
}
