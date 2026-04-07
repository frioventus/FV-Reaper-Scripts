-- ==========================================
-- FV TrackFlow - Database Editor
-- @noindex
-- ==========================================
if not reaper.ImGui_CreateContext then
  reaper.MB("Please install ReaImGui via ReaPack.", "Error", 0)
  return
end

local ctx = reaper.ImGui_CreateContext('FV TrackFlow Editor')
local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])")
local core_file = script_path .. "FV_TrackFlow_Core.lua"

local Core = dofile(core_file)
Core.Init(script_path)

local Editor = {}
Editor.search_text = ""
Editor.selected_node_id = nil 
Editor.node_to_delete = nil
Editor.show_delete_modal = false
Editor.show_tag_modal = false
Editor.unique_tags = {}

Editor.node_to_rename = nil
Editor.rename_text = ""
Editor.show_rename_modal = false

Editor.clip_tags = ""
Editor.clip_target = ""
Editor.clip_sends = {}
Editor.clip_mode = "NONE"

Editor.scan_path = string.gsub(reaper.GetResourcePath() .. "/TrackTemplates", "\\", "/")

-- ==========================================
-- HELPER FUNCTIONS
-- ==========================================
local function GetFileName(path)
    if not path or path == "" then return "" end
    return path:match("([^/\\]+)$") or path
end

local function NormalizeIndices(parent_id)
    local children = Core.TreeCache[parent_id or "root"]
    if not children then return end
    local sorted = {}
    for _, cid in ipairs(children) do table.insert(sorted, Core.Database[cid]) end
    table.sort(sorted, function(a, b)
        if a.is_folder ~= b.is_folder then return a.is_folder end
        local ia = a.orig_idx or 999999
        local ib = b.orig_idx or 999999
        if ia == ib then return string.lower(a.name) < string.lower(b.name) end
        return ia < ib
    end)
    for i, child in ipairs(sorted) do child.orig_idx = i * 10 end
    Core.is_dirty = true
end

local was_dirty = Core.is_dirty
for p_id, _ in pairs(Core.TreeCache) do
    NormalizeIndices(p_id)
end
Core.is_dirty = was_dirty 

local function GetSortedChildren(p_id)
    local children = Core.TreeCache[p_id]
    if not children then return {} end
    local sorted = {}
    for _, id in ipairs(children) do table.insert(sorted, id) end
    table.sort(sorted, function(a, b)
        local node_a = Core.Database[a]
        local node_b = Core.Database[b]
        if node_a.is_folder ~= node_b.is_folder then return node_a.is_folder end
        local ia = node_a.orig_idx or 999999
        local ib = node_b.orig_idx or 999999
        if ia == ib then return string.lower(node_a.name) < string.lower(node_b.name) end
        return ia < ib
    end)
    return sorted
end

local function GetMoveTarget(node_id, direction)
    local node = Core.Database[node_id]
    local p_id = node.parent_id or "root"
    local children = GetSortedChildren(p_id)
    
    local same_type_children = {}
    local my_idx = 1
    
    for _, cid in ipairs(children) do
        if Core.Database[cid].is_folder == node.is_folder then
            table.insert(same_type_children, cid)
            if cid == node_id then my_idx = #same_type_children end
        end
    end
    
    local target_idx = my_idx + direction
    if target_idx >= 1 and target_idx <= #same_type_children then
        return same_type_children[target_idx]
    end
    return nil
end

local function DrawMicroBadge(tag)
    local t_upper = string.upper(tag)
    local cfg = Core.tag_configs[t_upper] or { short = string.sub(t_upper, 1, 3), color = 0x9E9E9EFF }
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), cfg.color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), cfg.color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), cfg.color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x111111FF)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 3)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 5, 0)
    
    reaper.ImGui_Button(ctx, cfg.short)
    
    reaper.ImGui_PopStyleVar(ctx, 2)
    reaper.ImGui_PopStyleColor(ctx, 4)
end

-- ==========================================
-- SCANNER
-- ==========================================
local function GetOrCreateFolderHierarchy(relative_path_str)
    if not relative_path_str or relative_path_str == "" then return nil end
    local current_parent = nil
    for folder_name in string.gmatch(relative_path_str, "[^/]+") do
        local found_id = nil
        local children = Core.TreeCache[current_parent or "root"]
        if children then
            for _, child_id in ipairs(children) do
                local node = Core.Database[child_id]
                if node and node.is_folder and string.lower(node.name) == string.lower(folder_name) then
                    found_id = child_id; break
                end
            end
        end
        if not found_id then
            found_id = Core.GenerateID("fld")
            Core.Database[found_id] = {
                id = found_id, parent_id = current_parent, is_folder = true,
                name = folder_name, orig_idx = 999999
            }
            local p_key = current_parent or "root"
            if not Core.TreeCache[p_key] then Core.TreeCache[p_key] = {} end
            table.insert(Core.TreeCache[p_key], found_id)
            Core.TreeCache[found_id] = {}
        end
        current_parent = found_id
    end
    return current_parent
end

local function AddNewTemplateToDB(full_path, base_path)
    local safe_full_path = string.gsub(full_path, "\\", "/")
    local safe_base_path = string.gsub(base_path, "\\", "/")
    local new_file_name = string.lower(GetFileName(safe_full_path))
    local exists = false
    
    for _, item in pairs(Core.Database) do
        if not item.is_folder and string.lower(GetFileName(item.file_path)) == new_file_name then
            exists = true; break
        end
    end
    
    if not exists then
        local name_with_ext = safe_full_path:match("([^/]+)$") or ""
        local name_no_ext = name_with_ext:gsub("%.RTrackTemplate$", "")
        local relative_path = ""
        local start_idx = string.find(safe_full_path, safe_base_path, 1, true)
        if start_idx == 1 then
            local remainder = string.sub(safe_full_path, string.len(safe_base_path) + 2)
            relative_path = string.match(remainder, "^(.*)/") or ""
        end
        local parent_folder_id = GetOrCreateFolderHierarchy(relative_path)
        local item_id = Core.GenerateID("itm")
        
        Core.Database[item_id] = {
            id = item_id, parent_id = parent_folder_id, is_folder = false, name = name_no_ext,
            file_path = safe_full_path, target_folder = "", tags = {}, routing = { sends = {} },
            is_favorite = false, orig_idx = 999999
        }
        Core.is_dirty = true
        local p_key = parent_folder_id or "root"
        if not Core.TreeCache[p_key] then Core.TreeCache[p_key] = {} end
        table.insert(Core.TreeCache[p_key], item_id)
    end
end

local function ScanDirectory(current_path, base_path)
    local i = 0
    while true do
        local file = reaper.EnumerateFiles(current_path, i)
        if not file then break end
        if string.match(file, "%.RTrackTemplate$") then
            AddNewTemplateToDB(current_path .. "/" .. file, base_path)
        end
        i = i + 1
    end
    local j = 0
    while true do
        local subdir = reaper.EnumerateSubdirectories(current_path, j)
        if not subdir then break end
        ScanDirectory(current_path .. "/" .. subdir, base_path)
        j = j + 1
    end
end

local function ScanAndRebuild(scan_path)
    ScanDirectory(scan_path, scan_path)
    Core.BuildTreeCache()
    for p_id, _ in pairs(Core.TreeCache) do
        NormalizeIndices(p_id)
    end
end

-- ==========================================
-- MODALS & INSPECTOR
-- ==========================================
local function RenderModals()
    
    if Editor.show_rename_modal and Editor.node_to_rename then
        reaper.ImGui_OpenPopup(ctx, "Rename Folder")
        Editor.show_rename_modal = false
    end
    
    if reaper.ImGui_BeginPopupModal(ctx, "Rename Folder", nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
        reaper.ImGui_TextDisabled(ctx, "Enter new name for the folder:")
        reaper.ImGui_PushItemWidth(ctx, 250)
        local rv, nt = reaper.ImGui_InputText(ctx, "##rename_inp", Editor.rename_text)
        if rv then Editor.rename_text = nt end
        reaper.ImGui_PopItemWidth(ctx)
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x1E88E5FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x42A5F5FF)
        if reaper.ImGui_Button(ctx, "Save", 120) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) then
            if Editor.node_to_rename then
                Core.UpdateNodeProperty(Editor.node_to_rename, "name", Editor.rename_text)
            end
            Editor.node_to_rename = nil
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_PopStyleColor(ctx, 2)
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Cancel", 120) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
            Editor.node_to_rename = nil
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_EndPopup(ctx)
    end

    if Editor.show_tag_modal then
        Editor.unique_tags = {}
        local tag_set = {}
        for _, item in pairs(Core.Database) do
            if item.tags then for _, t in ipairs(item.tags) do tag_set[string.upper(t)] = true end end
        end
        for t, _ in pairs(Core.tag_configs) do tag_set[t] = true end
        for t, _ in pairs(tag_set) do table.insert(Editor.unique_tags, t) end
        table.sort(Editor.unique_tags)
        for _, t in ipairs(Editor.unique_tags) do
            if not Core.tag_configs[t] then Core.tag_configs[t] = { short = string.sub(t, 1, 3), color = 0x9E9E9EFF } end
        end
        reaper.ImGui_OpenPopup(ctx, "Tag Color & Name Manager"); Editor.show_tag_modal = false 
    end
    
    if reaper.ImGui_IsPopupOpen(ctx, "Tag Color & Name Manager") then
        reaper.ImGui_SetNextWindowSizeConstraints(ctx, 350, 200, 350, 500)
    end
    
    if reaper.ImGui_BeginPopupModal(ctx, "Tag Color & Name Manager", nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
        reaper.ImGui_TextDisabled(ctx, "Set custom colors and short names for tags.")
        reaper.ImGui_Spacing(ctx); reaper.ImGui_Separator(ctx); reaper.ImGui_Spacing(ctx)
        
        local tags_vis = reaper.ImGui_BeginChild(ctx, "TagsScroll", 0, 300, 0)
        if tags_vis then
            for _, tag in ipairs(Editor.unique_tags) do
                reaper.ImGui_AlignTextToFramePadding(ctx); reaper.ImGui_Text(ctx, tag)
                reaper.ImGui_SameLine(ctx, 130); reaper.ImGui_PushID(ctx, "sh_"..tag)
                reaper.ImGui_PushItemWidth(ctx, 60)
                local rv_s, ns = reaper.ImGui_InputText(ctx, "##short", Core.tag_configs[tag].short)
                if rv_s then Core.tag_configs[tag].short = string.sub(ns, 1, 4) end
                reaper.ImGui_PopItemWidth(ctx); reaper.ImGui_PopID(ctx)
                
                reaper.ImGui_SameLine(ctx, 200); reaper.ImGui_PushID(ctx, "col_"..tag)
                
                if reaper.ImGui_ColorButton(ctx, "btn_"..tag, Core.tag_configs[tag].color) then
                    reaper.ImGui_OpenPopup(ctx, "Picker_"..tag)
                end
                
                if reaper.ImGui_BeginPopup(ctx, "Picker_"..tag) then
                    local rv_c, nc = reaper.ImGui_ColorPicker4(ctx, "##cp_"..tag, Core.tag_configs[tag].color)
                    if rv_c then Core.tag_configs[tag].color = nc end
                    reaper.ImGui_Spacing(ctx)
                    if reaper.ImGui_Button(ctx, "Close & Apply", -1) then reaper.ImGui_CloseCurrentPopup(ctx) end
                    reaper.ImGui_EndPopup(ctx)
                end
                reaper.ImGui_PopID(ctx)
            end
        end
        reaper.ImGui_EndChild(ctx) 
        
        reaper.ImGui_Spacing(ctx); reaper.ImGui_Separator(ctx); reaper.ImGui_Spacing(ctx)
        if reaper.ImGui_Button(ctx, "Save & Close", 120) then
            local tags_filepath = script_path .. "tags_config.lua"
            local f = io.open(tags_filepath, "w")
            if f then
                f:write("-- Auto-generated tag configurations\nreturn {\n")
                for tag, data in pairs(Core.tag_configs) do
                    f:write(string.format("  [\"%s\"] = { short = \"%s\", color = 0x%08X },\n", tag, data.short, data.color & 0xFFFFFFFF))
                end
                f:write("}\n"); f:close()
            end
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Cancel", 100) then reaper.ImGui_CloseCurrentPopup(ctx) end
        reaper.ImGui_EndPopup(ctx)
    end

    if Editor.show_delete_modal and Editor.node_to_delete then
        reaper.ImGui_OpenPopup(ctx, "Confirm Delete"); Editor.show_delete_modal = false
    end
    if reaper.ImGui_BeginPopupModal(ctx, "Confirm Delete", nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xAA3333FF)
        if reaper.ImGui_Button(ctx, "Yes, Delete", 120) then
            if Editor.selected_node_id == Editor.node_to_delete then Editor.selected_node_id = nil end
            Core.Database[Editor.node_to_delete] = nil
            Core.is_dirty = true; Core.BuildTreeCache(); Editor.node_to_delete = nil
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Cancel", 100) then
            Editor.node_to_delete = nil; reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_EndPopup(ctx)
    end
end

-- ==========================================
-- INSPECTOR RENDERER
-- ==========================================
local function RenderInspector()
    if not Editor.selected_node_id or not Core.Database[Editor.selected_node_id] then
        reaper.ImGui_TextDisabled(ctx, "Select an item to view properties.")
        return
    end
    
    local node = Core.Database[Editor.selected_node_id]
    
    reaper.ImGui_TextDisabled(ctx, "INSPECTOR")
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    reaper.ImGui_TextDisabled(ctx, "Type: " .. (node.is_folder and "Virtual Folder" or "Track Template"))
    reaper.ImGui_Spacing(ctx)
    
    reaper.ImGui_Text(ctx, "Name:")
    reaper.ImGui_PushItemWidth(ctx, -1)
    local rv_name, n_name = reaper.ImGui_InputText(ctx, "##insp_name", node.name)
    if rv_name then Core.UpdateNodeProperty(node.id, "name", n_name) end
    reaper.ImGui_PopItemWidth(ctx)
    
    if node.is_folder then
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x1E88E5FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x42A5F5FF)
        if reaper.ImGui_Button(ctx, "Save Folder Name", 140) then
            Core.WriteDatabaseToDisk(script_path)
        end
        reaper.ImGui_PopStyleColor(ctx, 2)
    end
    
    if not node.is_folder then
        reaper.ImGui_Spacing(ctx)
        local rv_fav, n_fav = reaper.ImGui_Checkbox(ctx, "Pin to Favorites", node.is_favorite == true)
        if rv_fav then Core.UpdateNodeProperty(node.id, "is_favorite", n_fav) end
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Text(ctx, "Auto-Insert Target Track:")
        reaper.ImGui_PushItemWidth(ctx, -1)
        local rv_tgt, n_tgt = reaper.ImGui_InputText(ctx, "##insp_tgt", node.target_folder or "")
        if rv_tgt then Core.UpdateNodeProperty(node.id, "target_folder", n_tgt) end
        reaper.ImGui_PopItemWidth(ctx)
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Text(ctx, "Tags (Separate with ','):")
        local current_tags_str = node.tags and table.concat(node.tags, ", ") or ""
        reaper.ImGui_PushItemWidth(ctx, -1)
        local rv_tags, n_tags = reaper.ImGui_InputText(ctx, "##insp_tags", current_tags_str)
        if rv_tags then
            local new_tags = {}
            for str in string.gmatch(n_tags, "([^,]+)") do
                str = str:match("^%s*(.-)%s*$")
                if str ~= "" then table.insert(new_tags, string.upper(str)) end
            end
            Core.UpdateNodeProperty(node.id, "tags", new_tags)
        end
        reaper.ImGui_PopItemWidth(ctx)
        
        reaper.ImGui_Spacing(ctx); reaper.ImGui_Separator(ctx); reaper.ImGui_Spacing(ctx)
        
        reaper.ImGui_Text(ctx, "FX SENDS:")
        if reaper.ImGui_Button(ctx, "+ Add Send", -1) then
            if not node.routing then node.routing = { sends = {} } end
            table.insert(node.routing.sends, {target = "", level_db = 0.0}); Core.is_dirty = true
        end
        
        local sends_to_remove = {}
        if node.routing and node.routing.sends then
            for s_idx, send in ipairs(node.routing.sends) do
                reaper.ImGui_PushID(ctx, "insp_send_" .. s_idx)
                reaper.ImGui_Spacing(ctx)
                
                reaper.ImGui_PushItemWidth(ctx, -90)
                local rvt, nt = reaper.ImGui_InputText(ctx, "##tgt", send.target)
                if rvt then send.target = nt; Core.is_dirty = true end
                reaper.ImGui_PopItemWidth(ctx)
                
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "X", 20) then table.insert(sends_to_remove, s_idx) end
                
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "^", 20) and s_idx > 1 then
                    local temp = node.routing.sends[s_idx]
                    node.routing.sends[s_idx] = node.routing.sends[s_idx - 1]
                    node.routing.sends[s_idx - 1] = temp; Core.is_dirty = true
                end
                
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "v", 20) and s_idx < #node.routing.sends then
                    local temp = node.routing.sends[s_idx]
                    node.routing.sends[s_idx] = node.routing.sends[s_idx + 1]
                    node.routing.sends[s_idx + 1] = temp; Core.is_dirty = true
                end
                
                reaper.ImGui_PushItemWidth(ctx, -1)
                local rvl, nl = reaper.ImGui_SliderDouble(ctx, "##db", send.level_db, -60.0, 12.0, "%.1f dB")
                if rvl then send.level_db = nl; Core.is_dirty = true end
                reaper.ImGui_PopItemWidth(ctx)
                
                reaper.ImGui_PopID(ctx)
            end
            for r = #sends_to_remove, 1, -1 do
                table.remove(node.routing.sends, sends_to_remove[r]); Core.is_dirty = true
            end
        end
    end
end

local function FolderHasMatchingChildren(folder_id, lower_search)
    local children = Core.TreeCache[folder_id]
    if not children then return false end
    for _, child_id in ipairs(children) do
        local child = Core.Database[child_id]
        if child then
            if child.is_folder then
                if FolderHasMatchingChildren(child_id, lower_search) then return true end
            else
                if string.find(string.lower(child.name or ""), lower_search, 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

-- ==========================================
-- TREE-GRID RENDERER
-- ==========================================
local function RenderNodeRow(node_id, depth)
    local node = Core.Database[node_id]
    if not node then return end
    depth = depth or 0

    if Editor.search_text ~= "" then
        local lower_search = string.lower(Editor.search_text)
        local lower_name = string.lower(node.name or "")
        if node.is_folder then
            if not FolderHasMatchingChildren(node_id, lower_search) then return end
        else
            if not string.find(lower_name, lower_search, 1, true) then return end
        end
    end

    reaper.ImGui_PushID(ctx, "row_" .. tostring(node.id))
    reaper.ImGui_TableNextRow(ctx)
    reaper.ImGui_TableNextColumn(ctx)
    reaper.ImGui_AlignTextToFramePadding(ctx) 
    
    local start_pos_y = reaper.ImGui_GetCursorPosY(ctx)
    local col0_start_x = reaper.ImGui_GetCursorPosX(ctx)
    local is_selected = (Editor.selected_node_id == node.id)

    -- ==========================================
    -- FOLDER RENDERER
    -- ==========================================
    if node.is_folder then
        reaper.ImGui_SetCursorPosX(ctx, col0_start_x + (depth * 12.0))
        
        local t_flags = reaper.ImGui_TreeNodeFlags_OpenOnArrow() | reaper.ImGui_TreeNodeFlags_SpanFullWidth()
        if is_selected then t_flags = t_flags | reaper.ImGui_TreeNodeFlags_Selected() end
        if Editor.search_text ~= "" then t_flags = t_flags | reaper.ImGui_TreeNodeFlags_DefaultOpen() end
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0xFFFFFF15) 
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0xFFFFFF25)
        
        local safe_name = type(node.name) == "string" and node.name or "Unnamed Folder"
        local is_open = reaper.ImGui_TreeNodeEx(ctx, "tree_" .. tostring(node.id), safe_name, t_flags)
        
        if reaper.ImGui_IsItemClicked(ctx) and not reaper.ImGui_IsItemToggledOpen(ctx) then 
            Editor.selected_node_id = node.id 
        end
        
        reaper.ImGui_PopStyleColor(ctx, 2)
        
        if Editor.search_text == "" and reaper.ImGui_BeginDragDropSource(ctx) then
            reaper.ImGui_SetDragDropPayload(ctx, 'DND_NODE', node.id)
            reaper.ImGui_Text(ctx, "Moving Folder: " .. safe_name)
            reaper.ImGui_EndDragDropSource(ctx)
        end
        
        if Editor.search_text == "" and reaper.ImGui_BeginDragDropTarget(ctx) then
            local rv, payload_id = reaper.ImGui_AcceptDragDropPayload(ctx, 'DND_NODE')
            if rv and payload_id and payload_id ~= node.id then
                local src_node = Core.Database[payload_id]
                if src_node then
                    if src_node.is_folder then
                        local is_cyclic = false
                        local cur = node.id
                        while cur and cur ~= "" do
                            if cur == payload_id then is_cyclic = true break end
                            cur = Core.Database[cur] and Core.Database[cur].parent_id
                        end
                        if not is_cyclic then
                            local old_parent = src_node.parent_id
                            src_node.parent_id = node.id
                            NormalizeIndices(node.id)
                            if old_parent ~= node.id then NormalizeIndices(old_parent) end
                            Core.BuildTreeCache()
                        end
                    else
                        local old_parent = src_node.parent_id
                        src_node.parent_id = node.id
                        NormalizeIndices(node.id)
                        if old_parent ~= node.id then NormalizeIndices(old_parent) end
                        Core.BuildTreeCache()
                    end
                end
            end
            reaper.ImGui_EndDragDropTarget(ctx)
        end

        if reaper.ImGui_BeginPopupContextItem(ctx, "ctx_fld_" .. tostring(node.id)) then
            if reaper.ImGui_MenuItem(ctx, "Rename Folder...") then
                Editor.node_to_rename = node.id
                Editor.rename_text = safe_name
                Editor.show_rename_modal = true
            end
            reaper.ImGui_Separator(ctx)
            
            local target_up_id = GetMoveTarget(node.id, -1)
            if reaper.ImGui_MenuItem(ctx, "Move Up", nil, false, target_up_id ~= nil) then
                local target_node = Core.Database[target_up_id]
                local temp = node.orig_idx
                node.orig_idx = target_node.orig_idx
                target_node.orig_idx = temp
                NormalizeIndices(node.parent_id)
                Core.BuildTreeCache()
            end
            
            local target_down_id = GetMoveTarget(node.id, 1)
            if reaper.ImGui_MenuItem(ctx, "Move Down", nil, false, target_down_id ~= nil) then
                local target_node = Core.Database[target_down_id]
                local temp = node.orig_idx
                node.orig_idx = target_node.orig_idx
                target_node.orig_idx = temp
                NormalizeIndices(node.parent_id)
                Core.BuildTreeCache()
            end
            
            reaper.ImGui_Separator(ctx)
            if reaper.ImGui_MenuItem(ctx, "Create Subfolder Here") then
                local new_id = Core.GenerateID("fld")
                Core.Database[new_id] = { id = new_id, parent_id = node.id, is_folder = true, name = "New Folder", orig_idx = 999999 }
                Core.is_dirty = true; NormalizeIndices(node.id); Core.BuildTreeCache()
                Editor.selected_node_id = new_id
            end
            reaper.ImGui_Separator(ctx)
            
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xEF5350FF)
            if reaper.ImGui_MenuItem(ctx, "Delete...") then 
                Editor.node_to_delete = node.id
                Editor.show_delete_modal = true 
            end
            reaper.ImGui_PopStyleColor(ctx)
            
            reaper.ImGui_EndPopup(ctx)
        end
        
        reaper.ImGui_TableNextColumn(ctx) 
        reaper.ImGui_TableNextColumn(ctx) 

        if is_open then
            local sorted_children = GetSortedChildren(node.id)
            for _, child_id in ipairs(sorted_children) do 
                RenderNodeRow(child_id, depth + 1) 
            end
            reaper.ImGui_TreePop(ctx)
        end

    -- ==========================================
    -- TRACK RENDERER
    -- ==========================================
    else
        local item_cursor_x = col0_start_x + (depth * 12.0) + 16
        local name_cursor_x = item_cursor_x + 20 
        
        reaper.ImGui_SetCursorPosX(ctx, name_cursor_x)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0xFFFFFF15) 
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0xFFFFFF25)
        
        reaper.ImGui_SetNextItemAllowOverlap(ctx)
        local clicked = reaper.ImGui_Selectable(ctx, "##sel_" .. tostring(node.id), is_selected, reaper.ImGui_SelectableFlags_SpanAllColumns())
        if clicked then 
            Editor.selected_node_id = node.id 
        end
        
        local end_pos_y = reaper.ImGui_GetCursorPosY(ctx)
        reaper.ImGui_PopStyleColor(ctx, 2)
        
        local safe_name = type(node.name) == "string" and node.name or "Unnamed Track"

        if Editor.search_text == "" and reaper.ImGui_BeginDragDropSource(ctx) then
            reaper.ImGui_SetDragDropPayload(ctx, 'DND_NODE', node.id)
            reaper.ImGui_Text(ctx, "Moving Track: " .. safe_name)
            reaper.ImGui_EndDragDropSource(ctx)
        end
        
        if Editor.search_text == "" and reaper.ImGui_BeginDragDropTarget(ctx) then
            local rv, payload_id = reaper.ImGui_AcceptDragDropPayload(ctx, 'DND_NODE')
            if rv and payload_id and payload_id ~= node.id then
                local src_node = Core.Database[payload_id]
                if src_node and not src_node.is_folder then
                    local old_parent = src_node.parent_id
                    src_node.parent_id = node.parent_id
                    src_node.orig_idx = (node.orig_idx or 0) - 5
                    NormalizeIndices(node.parent_id)
                    if old_parent ~= node.parent_id then NormalizeIndices(old_parent) end
                    Core.BuildTreeCache()
                end
            end
            reaper.ImGui_EndDragDropTarget(ctx)
        end
        
        if reaper.ImGui_BeginPopupContextItem(ctx, "ctx_trk_" .. tostring(node.id)) then
            local target_up_id = GetMoveTarget(node.id, -1)
            if reaper.ImGui_MenuItem(ctx, "Move Up", nil, false, target_up_id ~= nil) then
                local target_node = Core.Database[target_up_id]
                local temp = node.orig_idx
                node.orig_idx = target_node.orig_idx
                target_node.orig_idx = temp
                NormalizeIndices(node.parent_id)
                Core.BuildTreeCache()
            end
            
            local target_down_id = GetMoveTarget(node.id, 1)
            if reaper.ImGui_MenuItem(ctx, "Move Down", nil, false, target_down_id ~= nil) then
                local target_node = Core.Database[target_down_id]
                local temp = node.orig_idx
                node.orig_idx = target_node.orig_idx
                target_node.orig_idx = temp
                NormalizeIndices(node.parent_id)
                Core.BuildTreeCache()
            end
        
            reaper.ImGui_Separator(ctx)
            
            if reaper.ImGui_MenuItem(ctx, "Copy Tags") then 
                Editor.clip_tags = node.tags and table.concat(node.tags, ", ") or ""
                Editor.clip_mode = "TAGS" 
            end
            if reaper.ImGui_MenuItem(ctx, "Copy Auto-Insert Target") then
                Editor.clip_target = node.target_folder or ""
                Editor.clip_mode = "TARGET"
            end
            if reaper.ImGui_MenuItem(ctx, "Copy Sends") then 
                Editor.clip_sends = {}
                if node.routing and node.routing.sends then
                    for _, s in ipairs(node.routing.sends) do
                        table.insert(Editor.clip_sends, {target = s.target, level_db = s.level_db})
                    end 
                end
                Editor.clip_mode = "SENDS" 
            end
            if reaper.ImGui_MenuItem(ctx, "Copy ALL Data") then 
                Editor.clip_tags = node.tags and table.concat(node.tags, ", ") or ""
                Editor.clip_target = node.target_folder or ""
                Editor.clip_sends = {}
                if node.routing and node.routing.sends then
                    for _, s in ipairs(node.routing.sends) do
                        table.insert(Editor.clip_sends, {target = s.target, level_db = s.level_db})
                    end 
                end
                Editor.clip_mode = "ALL" 
            end
            
            local paste_label = "Paste Data " .. (Editor.clip_mode ~= "NONE" and "(" .. Editor.clip_mode .. ")" or "")
            if reaper.ImGui_MenuItem(ctx, paste_label, nil, false, Editor.clip_mode ~= "NONE") then
                if Editor.clip_mode == "TAGS" or Editor.clip_mode == "ALL" then
                    local new_tags = {}
                    for str in string.gmatch(Editor.clip_tags, "([^,]+)") do
                        str = str:match("^%s*(.-)%s*$")
                        if str ~= "" then table.insert(new_tags, string.upper(str)) end
                    end
                    node.tags = new_tags
                end
                if Editor.clip_mode == "TARGET" or Editor.clip_mode == "ALL" then
                    Core.UpdateNodeProperty(node.id, "target_folder", Editor.clip_target or "")
                end
                if Editor.clip_mode == "SENDS" or Editor.clip_mode == "ALL" then
                    node.routing = { sends = {} }
                    for _, s in ipairs(Editor.clip_sends) do
                        table.insert(node.routing.sends, {target = s.target, level_db = s.level_db})
                    end
                end
                Core.is_dirty = true
            end

            reaper.ImGui_Separator(ctx)
            if reaper.ImGui_MenuItem(ctx, "Duplicate Item") then
                local new_id = Core.GenerateID("itm")
                local new_tags = {}
                if node.tags then for _, t in ipairs(node.tags) do table.insert(new_tags, t) end end
                local new_sends = {}
                if node.routing and node.routing.sends then
                    for _, s in ipairs(node.routing.sends) do
                        table.insert(new_sends, {target = s.target, level_db = s.level_db})
                    end
                end
                Core.Database[new_id] = {
                    id = new_id, parent_id = node.parent_id, is_folder = false,
                    name = node.name .. " (Copy)", file_path = node.file_path,
                    target_folder = node.target_folder or "", tags = new_tags,
                    routing = { sends = new_sends }, is_favorite = false,
                    orig_idx = (node.orig_idx or 0) + 1
                }
                Core.is_dirty = true
                NormalizeIndices(node.parent_id)
                Core.BuildTreeCache()
                Editor.selected_node_id = new_id
            end
            
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xEF5350FF)
            if reaper.ImGui_MenuItem(ctx, "Delete Template... (Del)") then 
                Editor.node_to_delete = node.id
                Editor.show_delete_modal = true 
            end
            reaper.ImGui_PopStyleColor(ctx)
            reaper.ImGui_EndPopup(ctx)
        end
        
        reaper.ImGui_SetCursorPos(ctx, name_cursor_x, start_pos_y)
        reaper.ImGui_Text(ctx, safe_name)
        
        if node.target_folder and node.target_folder ~= "" then
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_TextColored(ctx, 0xFFB74DFF, "[ -> " .. node.target_folder .. " ]")
        end

        local is_fav = node.is_favorite == true
        local star_color = is_fav and 0xFFC107FF or 0x555555FF
        reaper.ImGui_SetCursorPos(ctx, item_cursor_x, start_pos_y)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), star_color)
        reaper.ImGui_Text(ctx, is_fav and "★" or "☆")
        reaper.ImGui_PopStyleColor(ctx)
        
        reaper.ImGui_SetCursorPos(ctx, item_cursor_x, start_pos_y)
        if reaper.ImGui_InvisibleButton(ctx, "star_btn_"..tostring(node.id), 16, 16) then
            Core.UpdateNodeProperty(node.id, "is_favorite", not is_fav)
            Core.BuildTreeCache()
        end
        
        reaper.ImGui_SetCursorPosY(ctx, end_pos_y)
        reaper.ImGui_Dummy(ctx, 0, 0)

        reaper.ImGui_TableNextColumn(ctx)
        if not node.tags or #node.tags == 0 then 
            reaper.ImGui_TextDisabled(ctx, "-")
        else
            for t_idx, t in ipairs(node.tags) do
                DrawMicroBadge(t)
                if t_idx < #node.tags then reaper.ImGui_SameLine(ctx, 0, 4) end
            end
        end
        
        reaper.ImGui_TableNextColumn(ctx)
        local send_summary = "-"
        if node.routing and node.routing.sends and #node.routing.sends > 0 then
            local temp_sends = {}
            for _, s in ipairs(node.routing.sends) do table.insert(temp_sends, s.target) end
            send_summary = table.concat(temp_sends, ", ")
        end
        reaper.ImGui_TextDisabled(ctx, send_summary)
    end
    
    reaper.ImGui_PopID(ctx)
end

-- ==========================================
-- MAIN UI LOOP
-- ==========================================
local function loop()
    reaper.ImGui_SetNextWindowSize(ctx, 1100, 600, reaper.ImGui_Cond_FirstUseEver())
    
    -- FORCE UN-COLLAPSE (Fixes the stuck minimize issue on startup)
    reaper.ImGui_SetNextWindowCollapsed(ctx, false, reaper.ImGui_Cond_Appearing())
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), 0x0A0A0AFF)
    
    -- DISABLE MINIMIZE BUTTON (NoCollapse Flag)
    local window_flags = reaper.ImGui_WindowFlags_NoCollapse()
    local visible, open = reaper.ImGui_Begin(ctx, 'FV TrackFlow - Database Editor', true, window_flags)
    
    if visible then
        reaper.ImGui_PushItemWidth(ctx, 250)
        local changed, new_path = reaper.ImGui_InputText(ctx, "##ScanPath", Editor.scan_path)
        if changed then Editor.scan_path = new_path end
        reaper.ImGui_PopItemWidth(ctx)
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "BROWSE", 70) then
            if reaper.JS_Dialog_BrowseForFolder then
                local rv, folder = reaper.JS_Dialog_BrowseForFolder("Select Folder", Editor.scan_path)
                if rv == 1 and folder ~= "" then Editor.scan_path = string.gsub(folder, "\\", "/") end
            end
        end

        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "SCAN", 70) then ScanAndRebuild(Editor.scan_path) end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "ADD FILES", 80) then 
            local retval, filename = reaper.GetUserFileNameForRead(Editor.scan_path, "Select Track Template", "*.RTrackTemplate")
            if retval then
                AddNewTemplateToDB(filename, Editor.scan_path)
                Core.BuildTreeCache()
                NormalizeIndices(nil)
            end
        end
        
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Dummy(ctx, 20, 1)
        reaper.ImGui_SameLine(ctx)
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x8E24AAFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xAB47BCFF)
        if reaper.ImGui_Button(ctx, "TAG MANAGER", 110) then Editor.show_tag_modal = true end
        reaper.ImGui_PopStyleColor(ctx, 2)
        
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x1E88E5FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x42A5F5FF)
        if reaper.ImGui_Button(ctx, "SAVE SETTINGS", 120) then
            Core.WriteDatabaseToDisk(script_path)
            reaper.SetExtState("FV_TrackFlow", "NeedsReload", "1", false)
        end
        reaper.ImGui_PopStyleColor(ctx, 2)
        
        reaper.ImGui_Spacing(ctx); reaper.ImGui_Separator(ctx); reaper.ImGui_Spacing(ctx)

        reaper.ImGui_PushItemWidth(ctx, 300)
        local s_changed, new_search = reaper.ImGui_InputTextWithHint(ctx, "##SearchDB", "Search library...", Editor.search_text)
        if s_changed then Editor.search_text = new_search end
        reaper.ImGui_PopItemWidth(ctx)
        
        if reaper.ImGui_IsItemFocused(ctx) and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
            Editor.search_text = ""
        end
        
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextDisabled(ctx, "(Tip: Drag & Drop to reorder, click an item to edit its properties!)")

        reaper.ImGui_Spacing(ctx)

        local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
        local inspector_w = 320
        local show_inspector = (avail_w > 650)
        local table_w = show_inspector and (avail_w - inspector_w - 8) or 0

        local left_visible = reaper.ImGui_BeginChild(ctx, "LeftPanel", table_w, 0)
        if left_visible then
            local table_flags = reaper.ImGui_TableFlags_BordersInnerH() | reaper.ImGui_TableFlags_ScrollY() | 
                                reaper.ImGui_TableFlags_Resizable() | reaper.ImGui_TableFlags_BordersOuter()
            
            if reaper.ImGui_BeginTable(ctx, "FV_Database_Table", 3, table_flags) then
                reaper.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
                reaper.ImGui_TableSetupColumn(ctx, "Track Name (Folders)", reaper.ImGui_TableColumnFlags_WidthStretch(), 2.0)
                reaper.ImGui_TableSetupColumn(ctx, "Tags", reaper.ImGui_TableColumnFlags_WidthStretch(), 1.0)
                reaper.ImGui_TableSetupColumn(ctx, "Sends", reaper.ImGui_TableColumnFlags_WidthStretch(), 1.0)

                reaper.ImGui_TableHeadersRow(ctx)
                
                if Editor.search_text == "" then
                    reaper.ImGui_TableNextRow(ctx)
                    reaper.ImGui_TableNextColumn(ctx)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x888888FF)
                    reaper.ImGui_Selectable(ctx, "  [ + Root Directory ]", false, reaper.ImGui_SelectableFlags_SpanAllColumns())
                    reaper.ImGui_PopStyleColor(ctx)
                    
                    if reaper.ImGui_BeginDragDropTarget(ctx) then
                        local rv, payload_id = reaper.ImGui_AcceptDragDropPayload(ctx, 'DND_NODE')
                        if rv and payload_id then 
                            local src_node = Core.Database[payload_id]
                            if src_node then
                                local old_parent = src_node.parent_id
                                src_node.parent_id = nil
                                NormalizeIndices("root")
                                if old_parent and old_parent ~= "" then NormalizeIndices(old_parent) end
                                Core.BuildTreeCache() 
                            end
                        end
                        reaper.ImGui_EndDragDropTarget(ctx)
                    end
                end

                local sorted_roots = GetSortedChildren("root")
                for _, root_id in ipairs(sorted_roots) do RenderNodeRow(root_id, 0) end
                
                reaper.ImGui_EndTable(ctx)
            end
        end
        reaper.ImGui_EndChild(ctx)
        
        if show_inspector then
            reaper.ImGui_SameLine(ctx)
            local right_visible = reaper.ImGui_BeginChild(ctx, "RightPanel", inspector_w, 0)
            if right_visible then
                RenderInspector()
            end
            reaper.ImGui_EndChild(ctx) 
        end
        
        RenderModals()
        Core.CheckAndSave(script_path)

        -- ==========================================
        -- KLAVYE KISAYOLLARI
        -- ==========================================
        if Editor.selected_node_id and Core.Database[Editor.selected_node_id] then
            local sel_node = Core.Database[Editor.selected_node_id]
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_F2()) then
                if sel_node.is_folder then
                    Editor.node_to_rename = Editor.selected_node_id
                    Editor.rename_text = sel_node.name or ""
                    Editor.show_rename_modal = true
                end
            end
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete()) then
                if not reaper.ImGui_IsAnyItemActive(ctx) then
                    Editor.node_to_delete = Editor.selected_node_id
                    Editor.show_delete_modal = true
                end
            end
        end
    end
    
    reaper.ImGui_End(ctx)
    reaper.ImGui_PopStyleColor(ctx)
    
    if open then reaper.defer(loop) end
end

reaper.defer(loop)