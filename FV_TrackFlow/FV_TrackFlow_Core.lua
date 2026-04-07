-- ==========================================
-- FV TrackFlow - Core Engine
-- @noindex
-- ==========================================

local Core = {}

-- The definitive source of truth. Flat structure. Concept: id -> object
Core.Database = {} 

-- Transient cache for rendering. Concept: parent_id -> array of child_ids
Core.TreeCache = {} 
Core.tag_configs = {}

-- Dirty Flag pattern to prevent UI thread blocking during disk I/O
Core.is_dirty = false
local AUTO_SAVE_INTERVAL = 5.0 -- seconds
local last_save_time = reaper.time_precise()

-- Localized standard library functions for maximum performance inside loops
local s_lower = string.lower
local s_find = string.find
local s_len = string.len
local s_sub = string.sub
local t_insert = table.insert
local t_sort = table.sort
local m_huge = math.huge

local SCORE_MIN = -m_huge
local SCORE_MAX = m_huge

-- ==========================================
-- HELPER FUNCTIONS
-- ==========================================

-- Generates a unique ID for new nodes
function Core.GenerateID(prefix)
    return prefix .. "_" .. tostring(math.random(10000000, 99999999))
end

-- Extremely fast string matching algorithm
local function CalculateFuzzyScore(needle, haystack)
    local n_len = s_len(needle)
    local h_len = s_len(haystack)

    if n_len == 0 then return SCORE_MIN end
    if n_len > h_len then return SCORE_MIN end

    local lower_needle = s_lower(needle)
    local lower_haystack = s_lower(haystack)

    local exact_pos = s_find(lower_haystack, lower_needle, 1, true)
    if exact_pos then
        return SCORE_MAX - h_len - exact_pos
    end

    local score = 0
    local h_idx = 1
    local consecutive = 0

    for n_idx = 1, n_len do
        local n_char = s_sub(lower_needle, n_idx, n_idx)
        local match_found = false

        while h_idx <= h_len do
            local h_char = s_sub(lower_haystack, h_idx, h_idx)
            if n_char == h_char then
                match_found = true
                if consecutive > 0 then score = score + 5 + consecutive
                else score = score + 1 end
                
                if h_idx == 1 then score = score + 10
                else
                    local prev_char = s_sub(lower_haystack, h_idx - 1, h_idx - 1)
                    if prev_char == " " or prev_char == "/" or prev_char == "_" or prev_char == "-" then
                        score = score + 8
                    end
                end
                consecutive = consecutive + 1
                h_idx = h_idx + 1
                break
            else
                consecutive = 0
                score = score - 1
                h_idx = h_idx + 1
            end
        end
        if not match_found then return SCORE_MIN end
    end
    return score
end

-- Resolves the full path string by walking up the parent_id chain
local function GetNodeFullPath(id)
    local path_parts = {}
    local current_id = Core.Database[id] and Core.Database[id].parent_id
    
    while current_id and current_id ~= "" and Core.Database[current_id] do
        t_insert(path_parts, 1, Core.Database[current_id].name)
        current_id = Core.Database[current_id].parent_id
    end
    
    return table.concat(path_parts, " / ")
end

-- ==========================================
-- DATABASE MANAGEMENT
-- ==========================================

-- Rebuilds the adjacency list in O(n) time for UI rendering
function Core.BuildTreeCache()
    Core.TreeCache = {}
    Core.TreeCache["root"] = {} 

    for id, node in pairs(Core.Database) do
        local p_id = node.parent_id
        if p_id == nil or p_id == "" then
            t_insert(Core.TreeCache["root"], id)
        else
            if not Core.TreeCache[p_id] then Core.TreeCache[p_id] = {} end
            t_insert(Core.TreeCache[p_id], id)
        end
    end
end

-- Interface to modify database properties
function Core.UpdateNodeProperty(id, key, new_value)
    if Core.Database[id] and Core.Database[id][key] ~= new_value then
        Core.Database[id][key] = new_value
        Core.is_dirty = true
    end
end

-- Initializes the database from disk
function Core.Init(script_path)
    local db_file = script_path .. "database.lua"
    local tags_file = script_path .. "tags_config.lua"
    
    math.randomseed(math.floor(reaper.time_precise() * 100000))
    
    if reaper.file_exists(tags_file) then
        local ok, t = pcall(dofile, tags_file)
        if ok and type(t) == "table" then Core.tag_configs = t end
    end
    
    if reaper.file_exists(db_file) then
        local raw_data = dofile(db_file)
        Core.Database = raw_data or {}
        Core.BuildTreeCache()
        return true
    end
    
    return false
end

-- Serializes the flat database into a pure Lua string format
function Core.WriteDatabaseToDisk(script_path)
    local db_filepath = script_path .. "database.lua"
    local file = io.open(db_filepath, "w")
    if not file then return false end

    file:write("-- Auto-generated by FV_TrackFlow (Flat DB Architecture)\nreturn {\n")
    
    for id, item in pairs(Core.Database) do
        file:write("  [\"" .. id .. "\"] = {\n")
        file:write("    id = \"" .. id .. "\",\n")
        
        if item.parent_id and item.parent_id ~= "" then
            file:write("    parent_id = \"" .. item.parent_id .. "\",\n")
        else
            file:write("    parent_id = nil,\n")
        end
        
        file:write("    is_folder = " .. tostring(item.is_folder) .. ",\n")
        local safe_name = string.gsub(item.name or "", "\"", "\\\"")
        file:write("    name = \"" .. safe_name .. "\",\n")
        -- BUG FIX: orig_idx klasörler ve track'ler için ortak yazılıyor.
        -- Eski kodda sadece track'ler için yazılıyordu → klasör sırası reload'da sıfırlanıyordu.
        file:write("    orig_idx = " .. tostring(item.orig_idx or 0) .. ",\n")
        
        if not item.is_folder then
            local safe_path = string.gsub(item.file_path or "", "\\", "/")
            file:write("    file_path = \"" .. safe_path .. "\",\n")
            file:write("    target_folder = \"" .. (item.target_folder or "") .. "\",\n")
            file:write("    is_favorite = " .. tostring(item.is_favorite or false) .. ",\n")
            
            file:write("    tags = {")
            if item.tags then
                for i, t in ipairs(item.tags) do 
                    file:write("\"" .. string.upper(t) .. "\"" .. (i < #item.tags and ", " or "")) 
                end
            end
            file:write("},\n")
            
            file:write("    routing = {\n      sends = {\n")
            if item.routing and item.routing.sends then
                for _, send in ipairs(item.routing.sends) do
                    if send.target and send.target ~= "" then
                        file:write("        { target = \"" .. send.target .. "\", level_db = " .. tostring(send.level_db or 0) .. " },\n")
                    end
                end
            end
            file:write("      }\n    }\n")
        end
        
        file:write("  },\n")
    end
    
    file:write("}\n")
    file:close()
    return true
end

-- Checks dirty flag and saves asynchronously if interval passed
function Core.CheckAndSave(script_path)
    if not Core.is_dirty then return end
    
    local current_time = reaper.time_precise()
    if (current_time - last_save_time) >= AUTO_SAVE_INTERVAL then
        Core.WriteDatabaseToDisk(script_path)
        Core.is_dirty = false
        last_save_time = current_time
    end
end

-- ==========================================
-- TAGS MANAGER
-- ==========================================

function Core.GetAllTags()
    local tags_map = {}
    for _, item in pairs(Core.Database) do
        if not item.is_folder and item.tags then
            for _, t in ipairs(item.tags) do tags_map[string.upper(t)] = true end
        end
    end
    local tags_list = {}
    for t, _ in pairs(tags_map) do table.insert(tags_list, t) end
    table.sort(tags_list)
    return tags_list
end

function Core.GetTagColor(tag)
    local t = string.upper(tag)
    if Core.tag_configs[t] and Core.tag_configs[t].color then return Core.tag_configs[t].color end
    return 0x9E9E9EFF
end

function Core.GetTagShortName(tag)
    local t = string.upper(tag)
    if Core.tag_configs[t] and Core.tag_configs[t].short then return Core.tag_configs[t].short end
    local words = {}
    for w in string.gmatch(t, "%S+") do table.insert(words, w) end
    if #words == 1 then
        local first_char = string.sub(t, 1, 1); local rest = string.sub(t, 2); local consonants = string.gsub(rest, "[AEIOU]", "")
        local short = first_char .. string.sub(consonants, 1, 2)
        return #short >= 2 and short or string.sub(t, 1, 3)
    else
        local short = ""
        for i = 1, math.min(#words, 4) do short = short .. string.sub(words[i], 1, 1) end
        return short
    end
end

-- ==========================================
-- CACHE & SEARCH
-- ==========================================

function Core.UpdateCache(search_text, current_parent_id, prefs)
    local current_view = {}
    local use_fuzzy = prefs == nil or prefs.use_fuzzy ~= false
    local pos_words = {}
    local neg_words = {}
    
    if search_text ~= "" then
        for w in string.gmatch(s_lower(search_text), "%S+") do 
            if s_sub(w, 1, 1) == "-" then
                -- Tek basina eksi "-" ise yok say, degilse negatiflere at
                if s_len(w) > 1 then t_insert(neg_words, s_sub(w, 2)) end
            else
                t_insert(pos_words, w)
            end
        end
    end

    if #pos_words > 0 or #neg_words > 0 then
        -- Search flat dictionary O(n)
        for id, item in pairs(Core.Database) do
            if not item.is_folder then
                local lower_name = s_lower(item.name)
                local folder_path_str = s_lower(GetNodeFullPath(id))
                
                -- NEGATIF ARAMA KONTROLU
                local is_rejected = false
                for _, n_word in ipairs(neg_words) do
                    if s_find(lower_name, n_word, 1, true) or s_find(folder_path_str, n_word, 1, true) then
                        is_rejected = true; break
                    end
                    if item.tags then
                        for _, t in ipairs(item.tags) do
                            if s_find(s_lower(t), n_word, 1, true) then
                                is_rejected = true; break
                            end
                        end
                    end
                    if is_rejected then break end
                end
                
                -- Eger reddedilmediyse Pozitifleri kontrol et
                if not is_rejected then
                    local all_match = true
                    local total_score = 0
                    
                    if #pos_words == 0 then
                        item.search_score = 0
                        t_insert(current_view, { type = "item", id = id, data = item })
                    else
                        for _, word in ipairs(pos_words) do
                            local word_matched = false
                            local best_word_score = SCORE_MIN
                            
                            if s_find(lower_name, word, 1, true) then 
                                word_matched = true; best_word_score = math.max(best_word_score, 1000)
                            elseif s_find(folder_path_str, word, 1, true) then
                                word_matched = true; best_word_score = math.max(best_word_score, 500)
                            else
                                if item.tags then
                                    for _, t in ipairs(item.tags) do
                                        if s_find(s_lower(t), word, 1, true) then
                                            word_matched = true; best_word_score = math.max(best_word_score, 800)
                                            break
                                        end
                                    end
                                end
                            end
                            
                            if not word_matched and use_fuzzy then
                                local fz_name = CalculateFuzzyScore(word, lower_name)
                                if fz_name > SCORE_MIN then word_matched = true; best_word_score = math.max(best_word_score, fz_name) end
                                
                                if not word_matched and item.tags then
                                    for _, t in ipairs(item.tags) do
                                        local fz_tag = CalculateFuzzyScore(word, s_lower(t))
                                        if fz_tag > SCORE_MIN then word_matched = true; best_word_score = math.max(best_word_score, fz_tag) break end
                                    end
                                end
                                if not word_matched and folder_path_str ~= "" then
                                    local fz_fld = CalculateFuzzyScore(word, folder_path_str)
                                    if fz_fld > SCORE_MIN then word_matched = true; best_word_score = math.max(best_word_score, fz_fld) end
                                end
                            end
                            
                            if not word_matched then all_match = false break
                            else total_score = total_score + best_word_score end
                        end
                        
                        if all_match then
                            item.search_score = total_score
                            t_insert(current_view, { type = "item", id = id, data = item })
                        end
                    end
                end
            end
        end
    else
        -- Navigation Adjacency List O(1)
        local p_id = (current_parent_id == nil or current_parent_id == "") and "root" or current_parent_id
        local children = Core.TreeCache[p_id]
        
        if children then
            for _, child_id in ipairs(children) do
                local node = Core.Database[child_id]
                if node then
                    t_insert(current_view, { type = node.is_folder and "folder" or "item", id = child_id, data = node })
                end
            end
        end
    end

    local sort_fav = prefs and prefs.sort_fav_top
    
    if search_text ~= "" then
        t_sort(current_view, function(a, b)
            if sort_fav and a.data.is_favorite ~= b.data.is_favorite then return a.data.is_favorite == true end
            if a.data.search_score == b.data.search_score then return s_lower(a.data.name) < s_lower(b.data.name) end
            return a.data.search_score > b.data.search_score
        end)
    else
        t_sort(current_view, function(a, b)
            -- Her zaman klasörler en üstte
            if a.type ~= b.type then return a.type == "folder" end
            
            -- Öğeler için Favorileri en üste pinleme ayarı açıksa uygula
            if a.type == "item" and sort_fav and a.data.is_favorite ~= b.data.is_favorite then 
                return a.data.is_favorite == true 
            end
            
            -- FIX: Editördeki gibi custom index değerini kullan (Hem klasörler hem öğeler için)
            local ia = a.data.orig_idx or 999999
            local ib = b.data.orig_idx or 999999
            
            -- Eğer Drag & Drop ile sıralanmamışlarsa (veya aynı endekse sahiplerse) alfabetik olarak düş
            if ia == ib then 
                return s_lower(a.data.name) < s_lower(b.data.name) 
            end
            
            return ia < ib
        end)
    end
    
    return current_view
end

-- ==========================================
-- REAPER INSERTION LOGIC
-- ==========================================

function Core.InsertTrackTemplateList(items, block_name, is_drag_drop)
    if not items or #items == 0 then return false end
    local valid_items = {}
    local has_missing = false

    for i = 1, #items do
        local item = items[i]
        local template_path = item.file_path
        if not (string.match(template_path, "^[a-zA-Z]:") or string.match(template_path, "^/")) then
            template_path = reaper.GetResourcePath() .. "/TrackTemplates/" .. template_path
        end
        if reaper.file_exists(template_path) then
            item.is_missing = false; table.insert(valid_items, item)
        else
            item.is_missing = true; has_missing = true
        end
    end
    if #valid_items == 0 then return has_missing end

    reaper.Undo_BeginBlock(); reaper.PreventUIRefresh(1)
    local base_sel_track = reaper.GetSelectedTrack(0, 0)
    local global_close_amount = 0
    local global_close_track = nil

    if base_sel_track then
        local d = reaper.GetMediaTrackInfo_Value(base_sel_track, "I_FOLDERDEPTH")
        if d < 0 then global_close_amount = d; reaper.SetMediaTrackInfo_Value(base_sel_track, "I_FOLDERDEPTH", 0) end
    end

    local last_inserted_for_target = {}
    local target_folders_to_close = {} 
    local last_inserted_global = nil

    for i = 1, #valid_items do
        local item = valid_items[i]
        local template_path = item.file_path
        if not (string.match(template_path, "^[a-zA-Z]:") or string.match(template_path, "^/")) then
            template_path = reaper.GetResourcePath() .. "/TrackTemplates/" .. template_path
        end

        local target_found = false
        local target_name_lower = string.lower(item.target_folder or "")

        if not is_drag_drop and target_name_lower ~= "" then
            if last_inserted_for_target[target_name_lower] and reaper.ValidatePtr(last_inserted_for_target[target_name_lower], "MediaTrack*") then
                reaper.SetOnlyTrackSelected(last_inserted_for_target[target_name_lower])
                target_found = true
            else
                for j = 0, reaper.CountTracks(0) - 1 do
                    local t = reaper.GetTrack(0, j)
                    local _, t_name = reaper.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
                    if string.lower(t_name) == target_name_lower then
                        reaper.SetOnlyTrackSelected(t)
                        target_found = true
                        local depth = reaper.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
                        if depth <= 0 then
                            reaper.SetMediaTrackInfo_Value(t, "I_FOLDERDEPTH", 1)
                            target_folders_to_close[target_name_lower] = { track = nil, amount = depth - 1 }
                        end
                        break
                    end
                end
            end
        end

        if not target_found then
            if last_inserted_global and reaper.ValidatePtr(last_inserted_global, "MediaTrack*") then reaper.SetOnlyTrackSelected(last_inserted_global)
            elseif base_sel_track and reaper.ValidatePtr(base_sel_track, "MediaTrack*") then reaper.SetOnlyTrackSelected(base_sel_track)
            else reaper.Main_OnCommand(40297, 0) end
        end

        reaper.Main_openProject(template_path)
        local num_selected = reaper.CountSelectedTracks(0)
        
        if num_selected > 0 then
            local last_new_track = reaper.GetSelectedTrack(0, num_selected - 1)
            if target_found then
                last_inserted_for_target[target_name_lower] = last_new_track
                if target_folders_to_close[target_name_lower] then target_folders_to_close[target_name_lower].track = last_new_track end
            else
                last_inserted_global = last_new_track
                global_close_track = last_new_track
            end

            if item.routing and item.routing.sends then
                for k = 0, num_selected - 1 do
                    local new_track = reaper.GetSelectedTrack(0, k)
                    for _, send_data in ipairs(item.routing.sends) do
                        local fx_track = nil
                        for j = 0, reaper.CountTracks(0) - 1 do
                            local t = reaper.GetTrack(0, j)
                            local _, t_name = reaper.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
                            if t_name == send_data.target then fx_track = t break end
                        end
                        if fx_track then
                            local send_idx = reaper.CreateTrackSend(new_track, fx_track)
                            local level_val = 10 ^ ((send_data.level_db or 0) / 20)
                            reaper.SetTrackSendInfo_Value(new_track, 0, send_idx, "D_VOL", level_val)
                        end
                    end
                end
            end
        end
    end

    for _, data in pairs(target_folders_to_close) do
        if data.track and reaper.ValidatePtr(data.track, "MediaTrack*") then
            local d = reaper.GetMediaTrackInfo_Value(data.track, "I_FOLDERDEPTH")
            reaper.SetMediaTrackInfo_Value(data.track, "I_FOLDERDEPTH", d + data.amount)
        end
    end

    if global_close_track and global_close_amount < 0 then
        if reaper.ValidatePtr(global_close_track, "MediaTrack*") then
            local d = reaper.GetMediaTrackInfo_Value(global_close_track, "I_FOLDERDEPTH")
            reaper.SetMediaTrackInfo_Value(global_close_track, "I_FOLDERDEPTH", d + global_close_amount)
        end
    elseif not global_close_track and base_sel_track and global_close_amount < 0 then
        if reaper.ValidatePtr(base_sel_track, "MediaTrack*") then
            local d = reaper.GetMediaTrackInfo_Value(base_sel_track, "I_FOLDERDEPTH")
            reaper.SetMediaTrackInfo_Value(base_sel_track, "I_FOLDERDEPTH", d + global_close_amount)
        end
    end

    reaper.PreventUIRefresh(-1); reaper.TrackList_AdjustWindows(false); reaper.UpdateArrange()
    reaper.Undo_EndBlock(block_name or "Insert Multiple Templates", -1)
    return has_missing
end

function Core.InsertTrackTemplate(item, is_drag_drop)
    return Core.InsertTrackTemplateList({item}, "Insert Track Template: " .. item.name, is_drag_drop)
end

function Core.InsertRandomTemplate(filtered_list)
    if not filtered_list or #filtered_list == 0 then return false end
    local valid_items = {}
    for _, row in ipairs(filtered_list) do
        if row.type == "item" and not row.data.is_missing then table.insert(valid_items, row.data) end
    end
    if #valid_items == 0 then return false end

    math.randomseed(math.floor(reaper.time_precise() * 100000))
    local random_index = math.random(1, #valid_items)
    local selected = valid_items[random_index]
    
    return Core.InsertTrackTemplateList({selected}, "Insert Random: " .. selected.name, false)
end

return Core