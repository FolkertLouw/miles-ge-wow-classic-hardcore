-- Shared evidence utilities. All published payloads are immutable snapshots.
local SL = StitchLogger
local listeners, resets, flushers = {}, {}, {}
function SL.Copy(value)
  if type(value) ~= "table" then return value end
  local out = {}; for k,v in pairs(value) do out[k] = SL.Copy(v) end; return out
end
function SL.Subscribe(fn) listeners[#listeners+1] = fn end
function SL.OnReset(fn) resets[#resets+1] = fn end
function SL.OnFlush(fn) flushers[#flushers+1] = fn end
function SL.Notify(event) for _,fn in ipairs(listeners) do fn(event) end end
function SL.ResetTransient(reason) for _,fn in ipairs(resets) do fn(reason) end end
function SL.FlushPending(reason) for _,fn in ipairs(flushers) do fn(reason) end end
function SL.Active() return StitchLoggerDB and not StitchLoggerDB.paused end
function SL.SpellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return GetSpellInfo(id) end
end
function SL.ItemID(link) return type(link)=="string" and tonumber(link:match("item:(%d+)")) or nil end
function SL.NPCID(guid)
  return type(guid)=="string" and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")) or nil
end
function SL.Actor(unit)
  local actor = SL.UnitSnapshot(unit)
  if actor then actor.npcId = SL.NPCID(actor.guid) end
  return actor
end

-- Use the client's localized self-receipt formats, including positional placeholders.
local function patternFor(format)
  local out, order, index, nextArg = {"^"}, {}, 1, 1
  while index <= #format do
    local tail = format:sub(index)
    local token, pos, typ = tail:match("^(%%(%d+)%$([sd]))")
    if not token then token, typ = tail:match("^(%%([sd]))"); pos = nextArg end
    if token then
      out[#out+1] = typ == "d" and "(%d+)" or "(.-)"
      order[#order+1] = tonumber(pos); nextArg = nextArg+1; index = index+#token
    elseif tail:sub(1,2) == "%%" then out[#out+1] = "%%"; index=index+2
    else
      local c=format:sub(index,index)
      out[#out+1] = c:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
      index=index+1
    end
  end
  out[#out+1]="$"; return table.concat(out), order
end
local selfFormats = {
  {"LOOT_ITEM_SELF_MULTIPLE", "loot", true}, {"LOOT_ITEM_SELF", "loot"},
  {"LOOT_ITEM_CREATED_SELF_MULTIPLE", "created", true}, {"LOOT_ITEM_CREATED_SELF", "created"},
  {"LOOT_ITEM_PUSHED_SELF_MULTIPLE", "pushed", true}, {"LOOT_ITEM_PUSHED_SELF", "pushed"},
}
function SL.ParseLoot(message)
  for _,spec in ipairs(selfFormats) do
    local fmt=_G[spec[1]]
    if type(fmt)=="string" then
      local pattern,order=patternFor(fmt)
      local captures={message:match(pattern)}
      if #captures>0 then
        local args={}; for i,v in ipairs(captures) do args[order[i]]=v end
        local id=SL.ItemID(args[1]); local qty=spec[3] and tonumber(args[2]) or 1
        if id and qty and qty>0 then
          return { item=SL.ItemSnapshot(args[1],qty), receiptKind=spec[2], selfReceipt=true, format=spec[1] }
        end
      end
    end
  end
  return nil
end
function SL.RecordLootMessage(message)
  local parsed=SL.ParseLoot(tostring(message))
  if parsed then
    parsed.rawMessage=message; parsed.attribution="unassigned"
    SL.LogEvent("item_received",parsed)
  else
    SL.LogEvent("loot_message", {rawMessage=message, confidence="low", attribution="unparsed_or_other_player", items={}})
  end
end

-- Deterministic fingerprint for snapshots; no hashes or lossy concatenation.
function SL.Fingerprint(value)
  if type(value)~="table" then return type(value)..":"..tostring(value) end
  local keys={}; for k in pairs(value) do keys[#keys+1]=k end
  table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
  local result={}; for _,k in ipairs(keys) do result[#result+1]=SL.Fingerprint(k).."="..SL.Fingerprint(value[k]) end
  return "{"..table.concat(result,";").."}"
end
