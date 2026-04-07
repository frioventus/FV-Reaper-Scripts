-- @description FV TrackFlow
-- @author frioventus
-- @version 0.9.5
-- @category Productivity
-- @provides
--   [main] FV_TrackFlow_Editor.lua
--   [main] FV_TrackFlow_ThemeEditor.lua
--   [nomain] FV_TrackFlow_Core.lua
-- @about A fast, intelligent track template assistant.

if not reaper.ImGui_CreateContext then
  reaper.MB("Please install ReaImGui via ReaPack.", "Error", 0)
  return
end

local ctx = reaper.ImGui_CreateContext('FV TrackFlow')

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])")
local core_file = script_path .. "FV_TrackFlow_Core.lua"

if not reaper.file_exists(core_file) then
    reaper.MB("FV_TrackFlow_Core.lua not found in the script directory!", "Missing Core", 0)
    return
end

local Core = dofile(core_file)
local is_db_loaded = Core.Init(script_path)
local is_db_empty = not is_db_loaded or (next(Core.Database) == nil)

local cached_all_tags = Core.GetAllTags() 

local Theme = { colors = {}, sizes = {} }
local theme_data_file = script_path .. "theme_data.lua"
if reaper.file_exists(theme_data_file) then
    local ok, loaded = pcall(dofile, theme_data_file)
    if ok and type(loaded) == "table" then Theme = loaded end
end

-- ==========================================
-- TOOLBAR ICON STATE MANAGEMENT
-- ==========================================
local is_new_value, filename, sectionID, cmdID, mode, resolution, val, contextstr = reaper.get_action_context()

local function setToolbarState(isActive)
    if cmdID and cmdID > 0 then
        reaper.SetToggleCommandState(sectionID, cmdID, isActive and 1 or 0)
        reaper.RefreshToolbar2(sectionID, cmdID)
    end
end

reaper.atexit(function() setToolbarState(false) end)
setToolbarState(true)

-- ==========================================
-- CORE OPTIMIZATION: Local Function Caching
-- ==========================================
local r = reaper
local r_time_precise = r.time_precise
local r_GetExtState = r.GetExtState
local r_SetExtState = r.SetExtState
local r_HasExtState = r.HasExtState
local r_DeleteExtState = r.DeleteExtState
local r_file_exists = r.file_exists
local r_AddRemoveReaScript = r.AddRemoveReaScript
local r_Main_OnCommand = r.Main_OnCommand
local r_GetMousePosition = r.GetMousePosition
local r_GetTrackFromPoint = r.GetTrackFromPoint
local r_SetOnlyTrackSelected = r.SetOnlyTrackSelected
local r_CountTracks = r.CountTracks
local r_GetTrack = r.GetTrack

-- ==========================================
-- USER PREFERENCES (With strict defaults)
-- ==========================================
local function get_pref(key, default_val)
    local val = r_GetExtState("FV_TrackFlow_Prefs", key)
    if val == "" then return default_val end
    return val == "1"
end

local prefs = {
    sort_fav_top = get_pref("SortFavTop", true), 
    auto_clear_search = get_pref("AutoClear", false),
    use_fuzzy = get_pref("UseFuzzy", true),
    enable_randomizer = get_pref("EnableRandomizer", false)
}

-- ==========================================
-- MOTIVATIONAL QUOTES
-- ==========================================
local quotes = {
    "Make some noise.", "Trust your ears.", "Less is more.",
    "Finish that track.", "Embrace the mistakes.", "Silence is a canvas.",
    "Serve the song.", "Vibe over perfection.", "Find your frequency.",
    "Follow the groove.", "Hit record.", "Create, don't overthink.",
    "Let the music breathe.", "Start with a kick.", "Keep it simple.",
    "Drop the beat.", "Write, arrange, mix.", "Sculpt the sound.",
    "Enjoy the process.", "Capture the vibe."
}
math.randomseed(math.floor(r_time_precise() * 1000))
local current_quote = quotes[math.random(1, #quotes)]

-- ==========================================
-- NEW FLAT DB NAVIGATION STATE
-- ==========================================
local current_parent_id = nil
local nav_history = {} 
local search_text = ""
local last_search_text = ""
local last_parent_id = "INVALID"
local search_box_id = 0

local current_view = {}
local needs_update = true

local dragging_items = nil 
local kb_selection_idx = 0 
local selected_indices = {} 
local scroll_to_selection = false
local auto_select_first = false 

local missing_file_msg_time = 0 
local force_dock = nil
local delayed_update_time = 0 
local show_settings_modal = false 
local show_shortcuts_modal = false 

local last_saved_dock_id = tonumber(r_GetExtState("FV_TrackFlow", "LastDockID")) or 0

local function GetCurrentFolderName()
    if not current_parent_id then return "[ Root Directory ]" end
    local node = Core.Database[current_parent_id]
    return node and node.name or "Unknown Folder"
end

local function GetCurrentFolderPath()
    if not current_parent_id then return "/" end
    local path_parts = {}
    local curr = current_parent_id
    while curr and curr ~= "" and Core.Database[curr] do
        table.insert(path_parts, 1, Core.Database[curr].name)
        curr = Core.Database[curr].parent_id
    end
    return "/" .. table.concat(path_parts, "/")
end

local function RunScript(file_name)
    local spath = script_path .. file_name
    if r_file_exists(spath) then
        local cmd_id = r_AddRemoveReaScript(true, 0, spath, true)
        if cmd_id ~= 0 then r_Main_OnCommand(cmd_id, 0) end
    end
end

-- Centralized Context Menu
local function DrawMainContextMenu(ctx, is_docked)
    if r.ImGui_MenuItem(ctx, "Preferences...") then show_settings_modal = true end
    if r.ImGui_MenuItem(ctx, "Shortcuts...") then show_shortcuts_modal = true end
    r.ImGui_Separator(ctx)
    
    if prefs.enable_randomizer then
        if r.ImGui_MenuItem(ctx, "Insert Random Track (Global)") then
            local global_list = {}
            for _, item in pairs(Core.Database) do
                if not item.is_folder then table.insert(global_list, { type = "item", data = item }) end
            end
            if Core.InsertRandomTemplate(global_list) then
                missing_file_msg_time = r_time_precise()
            end
        end
        r.ImGui_Separator(ctx)
    end
    
    if r.ImGui_MenuItem(ctx, "Open Database Editor") then RunScript("FV_TrackFlow_Editor.lua") end
    if r.ImGui_MenuItem(ctx, "Open Theme Customizer") then RunScript("FV_TrackFlow_ThemeEditor.lua") end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, is_docked and "Undock Window" or "Dock Window") then
        if is_docked then force_dock = 0 else
            local last_dock = tonumber(r_GetExtState("FV_TrackFlow", "LastDockID"))
            force_dock = (last_dock and last_dock ~= 0) and last_dock or 2 
        end
    end
end

local function PushCustomTheme()
    local c = Theme.colors or {}
    local popup_bg = c.PopupBg or c.WindowBg or 0x1A1A1CFF
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), c.WindowBg or 0x1A1A1CFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), c.ChildBg or 0x1A1A1CFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), popup_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), c.FrameBg or 0x25262AFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), c.FrameBgHovered or 0x303238FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.Text or 0xDFDFDFFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), c.Header or 0x30323800) 
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), c.HeaderHovered or 0x303238FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), c.HeaderActive or 0x40424AFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), c.Button or 0x2A2C33FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), c.ButtonHovered or 0x3A3D45FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), c.ButtonActive or 0x4A4E58FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), c.Separator or 0x2A2C33FF) 
    
    local s = Theme.sizes or {}
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), s.FrameRounding or 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 8, 4)
end

local function PopCustomTheme()
    r.ImGui_PopStyleColor(ctx, 13)
    r.ImGui_PopStyleVar(ctx, 3)
end

local function DrawMicroBadge(tag, is_negative)
    local color = Core.GetTagColor(tag) 
    local short_name = Core.GetTagShortName(tag)
    
    if is_negative then
        color = (color & 0xFFFFFF00) | 0x33
        short_name = "-" .. short_name
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x888888FF)
    else
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x111111FF)
    end

    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), color)
    
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 5, 0)
    
    r.ImGui_Button(ctx, short_name)
    
    r.ImGui_PopStyleVar(ctx, 2)
    r.ImGui_PopStyleColor(ctx, 4)
end

local function DrawCenteredWrappedText(ctx, text, win_w, padding, is_disabled)
    local max_w = math.max(10, win_w - padding * 2)
    local words = {}
    for w in text:gmatch("%S+") do table.insert(words, w) end
    
    local line = ""
    for i, word in ipairs(words) do
        local test_line = line == "" and word or (line .. " " .. word)
        local w = r.ImGui_CalcTextSize(ctx, test_line)
        if w > max_w and line ~= "" then
            local lw = r.ImGui_CalcTextSize(ctx, line)
            r.ImGui_SetCursorPosX(ctx, math.max(padding, (win_w - lw) * 0.5))
            if is_disabled then r.ImGui_TextDisabled(ctx, line) else r.ImGui_Text(ctx, line) end
            line = word
        else
            line = test_line
        end
    end
    if line ~= "" then
        local lw = r.ImGui_CalcTextSize(ctx, line)
        r.ImGui_SetCursorPosX(ctx, math.max(padding, (win_w - lw) * 0.5))
        if is_disabled then r.ImGui_TextDisabled(ctx, line) else r.ImGui_Text(ctx, line) end
    end
end

local function DrawResponsiveCheckbox(ctx, label, value, modal_w)
    local rv, new_val = r.ImGui_Checkbox(ctx, "##chk_"..label, value)
    r.ImGui_SameLine(ctx)
    local text_start_x = r.ImGui_GetCursorPosX(ctx)
    local available_w = math.max(50, modal_w - text_start_x - 8)
    r.ImGui_PushTextWrapPos(ctx, text_start_x + available_w)
    r.ImGui_Text(ctx, label)
    r.ImGui_PopTextWrapPos(ctx)
    if r.ImGui_IsItemClicked(ctx) then new_val = not value; rv = true end
    return rv, new_val
end

local function ExecuteInsertion(items, block_name, is_drag_drop)
    if Core.InsertTrackTemplateList(items, block_name, is_drag_drop) then
        missing_file_msg_time = r_time_precise()
    end
    if prefs.auto_clear_search and search_text ~= "" then
        search_text = ""
        search_box_id = search_box_id + 1
        needs_update = true
    end
    selected_indices = {} 
    kb_selection_idx = 0
end

local function loop()
  if r_HasExtState("FV_TrackFlow", "NeedsReload") then
      r_DeleteExtState("FV_TrackFlow", "NeedsReload", true)
      is_db_loaded = Core.Init(script_path)
      is_db_empty = not is_db_loaded or (next(Core.Database) == nil)
      cached_all_tags = Core.GetAllTags() 
      
      if reaper.file_exists(theme_data_file) then
          local ok, loaded = pcall(dofile, theme_data_file)
          if ok and type(loaded) == "table" then Theme = loaded end
      end
      needs_update = true
  end

  PushCustomTheme()
  r.ImGui_SetNextWindowSize(ctx, 350, 500, r.ImGui_Cond_FirstUseEver())
  
  if force_dock ~= nil then
      r.ImGui_SetNextWindowDockID(ctx, force_dock)
      force_dock = nil
  end
  
  local visible, open = r.ImGui_Begin(ctx, 'FV TrackFlow', true, r.ImGui_WindowFlags_NoCollapse())
  
  if visible then
    local is_main_window_docked = r.ImGui_IsWindowDocked(ctx)
    local current_dock_id = r.ImGui_GetWindowDockID(ctx)

    if is_main_window_docked and current_dock_id ~= 0 and current_dock_id ~= last_saved_dock_id then
        r_SetExtState("FV_TrackFlow", "LastDockID", tostring(current_dock_id), true)
        last_saved_dock_id = current_dock_id
    end
    
    if delayed_update_time > 0 and r_time_precise() > delayed_update_time then
        needs_update = true
        delayed_update_time = 0
    end

    if r.ImGui_BeginPopupContextWindow(ctx, "FV_ContextMenu_Main", 1) then
        DrawMainContextMenu(ctx, is_main_window_docked)
        r.ImGui_EndPopup(ctx)
    end

    if is_db_empty then
        local win_w = r.ImGui_GetWindowWidth(ctx)
        local win_h = r.ImGui_GetWindowHeight(ctx)
        local padding = 15 
        r.ImGui_SetCursorPosY(ctx, math.max(padding, (win_h - 150) * 0.5))
        DrawCenteredWrappedText(ctx, "Welcome to FV TrackFlow 🌊", win_w, padding, false)
        r.ImGui_Spacing(ctx)
        DrawCenteredWrappedText(ctx, "Your database is empty or missing.", win_w, padding, true)
        r.ImGui_Spacing(ctx); r.ImGui_Spacing(ctx); r.ImGui_Spacing(ctx)
        
        local btn_label = "Open Database Editor"
        local btn_w = math.min(200, math.max(80, win_w - (padding * 2)))
        r.ImGui_SetCursorPosX(ctx, math.max(padding, (win_w - btn_w) * 0.5))
        
        local c = Theme.colors or {}
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), c.HeaderActive or 0x40424AFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), c.ButtonHovered or 0x3A3D45FF)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6)
        
        if r.ImGui_Button(ctx, btn_label, btn_w, 35) then RunScript("FV_TrackFlow_Editor.lua") end
        
        r.ImGui_PopStyleVar(ctx)
        r.ImGui_PopStyleColor(ctx, 2)
        r.ImGui_Spacing(ctx); r.ImGui_Spacing(ctx)
        DrawCenteredWrappedText(ctx, "Right-Click anywhere for options.", win_w, padding, true)
        
    else
        local win_w = r.ImGui_GetWindowWidth(ctx)
        local current_nav_str = current_parent_id or "ROOT"
        local c = Theme.colors or {}
        
        if search_text ~= last_search_text or current_nav_str ~= last_parent_id or needs_update then
            current_view = Core.UpdateCache(search_text, current_parent_id, prefs) 
            last_search_text = search_text
            last_parent_id = current_nav_str
            needs_update = false
            selected_indices = {} 
            
            if auto_select_first and current_view and #current_view > 0 then
                kb_selection_idx = 1
                selected_indices[1] = true
            else
                kb_selection_idx = 0
            end
            auto_select_first = false 
        end

        local is_ctrl = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Super())
        local is_shift = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift())
        local force_focus_search = false
        local is_esc_pressed = false

        if r.ImGui_IsWindowAppearing(ctx) then force_focus_search = true end
        
        if r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows()) then
            
            if is_ctrl and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_E(), false) then RunScript("FV_TrackFlow_Editor.lua") end
            if is_ctrl and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_T(), false) then RunScript("FV_TrackFlow_ThemeEditor.lua") end
            if is_ctrl and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_F(), false) then force_focus_search = true end

            if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
                is_esc_pressed = true
                if search_text ~= "" then 
                    search_text = ""
                    search_box_id = search_box_id + 1
                    auto_select_first = true 
                    needs_update = true
                elseif current_parent_id then 
                    current_parent_id = table.remove(nav_history)
                    auto_select_first = true 
                    needs_update = true 
                end
            end
            if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_DownArrow()) then
                kb_selection_idx = kb_selection_idx + 1
                if kb_selection_idx > #current_view then kb_selection_idx = #current_view end
                selected_indices = {[kb_selection_idx] = true} 
                scroll_to_selection = true
                force_focus_search = true 
            end
            if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_UpArrow()) then
                kb_selection_idx = kb_selection_idx - 1
                if kb_selection_idx < 1 then kb_selection_idx = 1 end
                if #current_view == 0 then kb_selection_idx = 0 end
                selected_indices = {[kb_selection_idx] = true} 
                scroll_to_selection = true
                force_focus_search = true
            end
            if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) then
                local sel_count = 0
                for k, v in pairs(selected_indices) do if v then sel_count = sel_count + 1 end end
                if sel_count > 1 then
                    local items = {}
                    for idx, row in ipairs(current_view) do
                        if selected_indices[idx] and row.type == "item" and not row.data.is_missing then table.insert(items, row.data) end
                    end
                    if #items > 0 then ExecuteInsertion(items, "Insert Selected Templates", false) end
                elseif kb_selection_idx > 0 and current_view[kb_selection_idx] then
                    local row = current_view[kb_selection_idx]
                    if row.type == "folder" then
                        table.insert(nav_history, current_parent_id)
                        current_parent_id = row.id
                        if search_text ~= "" then
                            search_text = ""
                            search_box_id = search_box_id + 1
                        end
                        auto_select_first = true 
                        needs_update = true
                    elseif not row.data.is_missing then
                        ExecuteInsertion({row.data}, "Insert Track Template", false)
                    end
                end
            end
        end

        local show_x = search_text ~= ""
        local show_home = search_text == "" and current_parent_id ~= nil
        local right_space = (show_x or show_home) and -30 or -1

        if force_focus_search then r.ImGui_SetKeyboardFocusHere(ctx) end

        r.ImGui_PushItemWidth(ctx, right_space)
        local changed, new_search = r.ImGui_InputTextWithHint(ctx, '##Search_' .. search_box_id, 'Search or type tags...', search_text)
        r.ImGui_PopItemWidth(ctx)

        if changed and not is_esc_pressed then 
            search_text = new_search 
            needs_update = true 
        end
        
        if show_x then
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "X", 26) then 
                search_text = ""
                search_box_id = search_box_id + 1
                needs_update = true 
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Clear Search") end
        elseif show_home then
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "▲", 26) then 
                current_parent_id = nil
                nav_history = {}
                needs_update = true 
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Return to Root") end
        end
        
        r.ImGui_Spacing(ctx)

        local show_missing_text = (r_time_precise() - missing_file_msg_time) < 2.0
        
        local header_sel_items = {}
        for i, row in ipairs(current_view) do
            if selected_indices[i] and row.type == "item" and not row.data.is_missing then table.insert(header_sel_items, row.data) end
        end

        if r.ImGui_BeginChild(ctx, "NavHeader", 0, 22, 0) then
            if r.ImGui_BeginPopupContextWindow(ctx, "FV_ContextMenu_Nav", 1) then
                DrawMainContextMenu(ctx, is_main_window_docked)
                r.ImGui_EndPopup(ctx)
            end
            
            local header_start_x = r.ImGui_GetCursorPosX(ctx)
            
            if search_text == "" then
                if current_parent_id then
                    if r.ImGui_Button(ctx, "<", 20) then 
                        current_parent_id = table.remove(nav_history)
                        needs_update = true 
                    end
                    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Go Back") end
                    r.ImGui_SameLine(ctx)
                    
                    r.ImGui_AlignTextToFramePadding(ctx)
                    if show_missing_text then
                        r.ImGui_TextColored(ctx, 0xFF5555FF, "File not found.")
                    else
                        local current_folder = GetCurrentFolderName()
                        r.ImGui_Text(ctx, current_folder)
                        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, GetCurrentFolderPath()) end
                    end
                else
                    if #header_sel_items > 0 then
                        local btn_label = "[+] INSERT SELECTED (" .. #header_sel_items .. ")"
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.InsertBtnText or 0x66BB6AFF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0) 
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), c.InsertBtnHover or 0x66BB6A33) 
                        
                        local text_w = r.ImGui_CalcTextSize(ctx, btn_label)
                        local btn_w = text_w + 16
                        local child_w = r.ImGui_GetWindowWidth(ctx)
                        r.ImGui_SetCursorPosX(ctx, math.max(header_start_x + 4, (child_w - btn_w) * 0.5))
                        
                        if r.ImGui_Button(ctx, btn_label) then ExecuteInsertion(header_sel_items, "Insert From Root", false) end
                        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Insert selected tracks directly") end
                        
                        r.ImGui_PopStyleColor(ctx, 3)
                    else
                        r.ImGui_SetCursorPosX(ctx, header_start_x + 4)
                        r.ImGui_AlignTextToFramePadding(ctx)
                        if show_missing_text then r.ImGui_TextColored(ctx, 0xFF5555FF, "File not found.") 
                        else r.ImGui_TextColored(ctx, c.QuotesText or 0x888888FF, current_quote) end
                    end
                end
            else
                if #header_sel_items > 0 then
                    local btn_label = "[+] INSERT SELECTED (" .. #header_sel_items .. ")"
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.InsertBtnText or 0x66BB6AFF)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0) 
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), c.InsertBtnHover or 0x66BB6A33) 
                    
                    local text_w = r.ImGui_CalcTextSize(ctx, btn_label)
                    local btn_w = text_w + 16
                    local child_w = r.ImGui_GetWindowWidth(ctx)
                    r.ImGui_SetCursorPosX(ctx, math.max(header_start_x + 4, (child_w - btn_w) * 0.5))
                    
                    if r.ImGui_Button(ctx, btn_label) then ExecuteInsertion(header_sel_items, "Insert From Search", false) end
                    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Insert selected tracks directly") end
                    
                    r.ImGui_PopStyleColor(ctx, 3)
                else
                    r.ImGui_SetCursorPosX(ctx, header_start_x + 4)
                    r.ImGui_AlignTextToFramePadding(ctx)
                    if show_missing_text then r.ImGui_TextColored(ctx, 0xFF5555FF, "File not found.")
                    else
                        local pos_words = {}
                        local neg_words = {}
                        for w in string.gmatch(string.lower(search_text), "%S+") do
                            if string.sub(w, 1, 1) == "-" then
                                if string.len(w) > 1 then table.insert(neg_words, string.sub(w, 2)) end
                            else
                                table.insert(pos_words, w)
                            end
                        end
                        
                        local active_pos_tags = {}
                        local active_neg_tags = {}
                        
                        for _, tag in ipairs(cached_all_tags) do
                            local tag_lower = string.lower(tag)
                            local short_lower = string.lower(Core.GetTagShortName(tag))
                            
                            for _, w in ipairs(pos_words) do
                                if string.find(tag_lower, w, 1, true) or string.find(short_lower, w, 1, true) then
                                    table.insert(active_pos_tags, tag)
                                    break
                                end
                            end
                            for _, w in ipairs(neg_words) do
                                if string.find(tag_lower, w, 1, true) or string.find(short_lower, w, 1, true) then
                                    table.insert(active_neg_tags, tag)
                                    break
                                end
                            end
                        end
                        
                        if #active_pos_tags > 0 or #active_neg_tags > 0 then
                            for _, tag in ipairs(active_pos_tags) do DrawMicroBadge(tag, false); r.ImGui_SameLine(ctx, 0, 4) end
                            for _, tag in ipairs(active_neg_tags) do DrawMicroBadge(tag, true); r.ImGui_SameLine(ctx, 0, 4) end
                            r.ImGui_TextDisabled(ctx, " found " .. #current_view)
                        else 
                            r.ImGui_TextDisabled(ctx, "Results for: " .. search_text) 
                        end
                    end
                end
            end
            r.ImGui_EndChild(ctx)
        end
        
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), c.ButtonHovered or 0x3A3D45FF)
        r.ImGui_Separator(ctx)
        r.ImGui_PopStyleColor(ctx)

        if r.ImGui_BeginChild(ctx, "ListArea", 0, 0, 0) then
            if r.ImGui_BeginPopupContextWindow(ctx, "FV_ContextMenu_List", 1) then
                DrawMainContextMenu(ctx, is_main_window_docked)
                r.ImGui_EndPopup(ctx)
            end
            
            local items_to_insert = {}
            local any_item_clicked = false 

            local avail_w = r.ImGui_GetContentRegionAvail(ctx)
            local min_col_width = 220 
            local num_cols = math.max(1, math.floor(avail_w / min_col_width))

            if #current_view > 0 then
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CellPadding(), 4, Theme.sizes.ItemSpacing_Y or 4)
                
                if r.ImGui_BeginTable(ctx, "GridTable_Main", num_cols, r.ImGui_TableFlags_SizingStretchProp()) then
                    for i, row in ipairs(current_view) do
                        r.ImGui_TableNextColumn(ctx)

                        local is_selected = selected_indices[i] == true
                        local active_color = c.HeaderActive or 0x40424AFF
                        
                        r.ImGui_PushID(ctx, "row_" .. i)
                        if is_selected then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), active_color) end

                        local start_pos_x = r.ImGui_GetCursorPosX(ctx)
                        local start_pos_y = r.ImGui_GetCursorPosY(ctx)

                        if row.type == "folder" then
                            local clicked = r.ImGui_Selectable(ctx, "##fld_"..row.id, is_selected)
                            local end_pos_y = r.ImGui_GetCursorPosY(ctx)
                            
                            if clicked then 
                                any_item_clicked = true
                                table.insert(nav_history, current_parent_id)
                                current_parent_id = row.id
                                if search_text ~= "" then
                                    search_text = ""
                                    search_box_id = search_box_id + 1
                                end
                                auto_select_first = false 
                                needs_update = true
                            end

                            r.ImGui_SetCursorPos(ctx, start_pos_x + 4, start_pos_y)
                            local folder_color = c.FolderText or 0xA0A0A0FF
                            r.ImGui_TextColored(ctx, folder_color, "+")
                            
                            r.ImGui_SetCursorPos(ctx, start_pos_x + 24, start_pos_y) 
                            r.ImGui_TextColored(ctx, folder_color, row.data.name)
                            
                            r.ImGui_SetCursorPosY(ctx, end_pos_y)
                            
                            if is_selected and scroll_to_selection then 
                                r.ImGui_SetScrollHereY(ctx, 0.5)
                                scroll_to_selection = false 
                            end
                            r.ImGui_Separator(ctx)
                            
                        elseif row.type == "item" then
                            local item = row.data
                            
                            local sel_flags = r.ImGui_SelectableFlags_AllowDoubleClick()
                            if item.is_missing then sel_flags = sel_flags | r.ImGui_SelectableFlags_Disabled() end

                            if not item.is_missing then table.insert(items_to_insert, item) end
                            
                            r.ImGui_SetNextItemAllowOverlap(ctx)
                            local clicked = r.ImGui_Selectable(ctx, "##sel_"..item.id, is_selected, sel_flags)
                            
                            local selectable_active = r.ImGui_IsItemActive(ctx)
                            local item_hovered = r.ImGui_IsItemHovered(ctx, r.ImGui_HoveredFlags_RectOnly())
                            local end_pos_y = r.ImGui_GetCursorPosY(ctx)
                            
                            local star_hovered = false
                            local star_active = false
                            local is_fav = item.is_favorite == true
                            
                            if (item_hovered or is_fav) and not item.is_missing then
                                r.ImGui_SetCursorPos(ctx, start_pos_x + 4, start_pos_y)
                                r.ImGui_InvisibleButton(ctx, "star_btn_"..item.id, 16, 16)
                                
                                star_hovered = r.ImGui_IsItemHovered(ctx)
                                star_active = r.ImGui_IsItemActive(ctx)
                                
                                if r.ImGui_IsItemClicked(ctx) then
                                    Core.UpdateNodeProperty(item.id, "is_favorite", not is_fav)
                                    delayed_update_time = r_time_precise() + 1.0 
                                end
                                
                                if star_hovered then
                                    if r.ImGui_BeginTooltip(ctx) then
                                        r.ImGui_Text(ctx, is_fav and "Remove from Favorites" or "Add to Favorites")
                                        r.ImGui_EndTooltip(ctx)
                                    end
                                end
                                
                                r.ImGui_SetCursorPos(ctx, start_pos_x + 4, start_pos_y)
                                local star_color = is_fav and 0xFFC107FF or 0x777777FF
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), star_color)
                                r.ImGui_Text(ctx, is_fav and "★" or "☆")
                                r.ImGui_PopStyleColor(ctx)
                            end
                            
                            if clicked and star_hovered then clicked = false end
                            
                            if clicked and not item.is_missing then
                                any_item_clicked = true
                                if r.ImGui_IsMouseDoubleClicked(ctx, 0) then
                                    ExecuteInsertion({item}, "Insert Track Template", false)
                                else
                                    if is_shift and kb_selection_idx > 0 then
                                        selected_indices = {}
                                        local min_i = math.min(kb_selection_idx, i)
                                        local max_i = math.max(kb_selection_idx, i)
                                        for j = min_i, max_i do selected_indices[j] = true end
                                    elseif is_ctrl then
                                        selected_indices[i] = not selected_indices[i]
                                        kb_selection_idx = i
                                    else
                                        selected_indices = {}
                                        selected_indices[i] = true
                                        kb_selection_idx = i
                                    end
                                end
                            end
                            
                            if is_selected and scroll_to_selection then 
                                r.ImGui_SetScrollHereY(ctx, 0.5)
                                scroll_to_selection = false 
                            end
                            
                            if selectable_active and not star_active and r.ImGui_IsMouseDragging(ctx, 0) and not item.is_missing then
                                if not selected_indices[i] then
                                    selected_indices = {[i] = true}
                                    kb_selection_idx = i
                                end
                                if not dragging_items then
                                    dragging_items = {}
                                    for idx, r_row in ipairs(current_view) do
                                        if selected_indices[idx] and r_row.type == "item" and not r_row.data.is_missing then
                                            table.insert(dragging_items, r_row.data)
                                        end
                                    end
                                end
                            end
                            
                            if item_hovered and not dragging_items and not star_hovered then
                                if item.is_missing then
                                    if r.ImGui_BeginTooltip(ctx) then
                                        r.ImGui_TextColored(ctx, 0xFF5555FF, "File is missing from disk!")
                                        r.ImGui_EndTooltip(ctx)
                                    end
                                else
                                    if r.ImGui_BeginTooltip(ctx) then
                                        r.ImGui_Text(ctx, "Double-click, Enter or Drag to add.")
                                        if item.target_folder and item.target_folder ~= "" then
                                            local target_col = c.AutoTargetText or 0xFFB74DFF 
                                            r.ImGui_TextColored(ctx, target_col, "Auto-Target: [ " .. item.target_folder .. " ]")
                                        end
                                        if item.tags and #item.tags > 0 then
                                            r.ImGui_Separator(ctx)
                                            for _, tag in ipairs(item.tags) do DrawMicroBadge(tag, false); r.ImGui_SameLine(ctx, 0, 4) end
                                        end
                                        r.ImGui_EndTooltip(ctx)
                                    end
                                end
                            end

                            r.ImGui_SetCursorPos(ctx, start_pos_x + 24, start_pos_y)
                            if item.is_missing then r.ImGui_TextColored(ctx, 0xFF5555FF, "[!] " .. item.name)
                            else r.ImGui_Text(ctx, item.name) end
                            
                            r.ImGui_SetCursorPosY(ctx, end_pos_y)
                            r.ImGui_Separator(ctx)
                        end
                        
                        if is_selected then r.ImGui_PopStyleColor(ctx) end
                        r.ImGui_PopID(ctx)
                    end
                    
                    r.ImGui_EndTable(ctx)
                end
                
                r.ImGui_PopStyleVar(ctx)
            end

            if r.ImGui_IsWindowHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 0) and not any_item_clicked then
                kb_selection_idx = 0
                selected_indices = {}
            end

            if not needs_update and #items_to_insert > 0 then
                r.ImGui_Spacing(ctx)
                
                if search_text == "" and current_parent_id then
                    local btn_label = "[+] INSERT ALL"
                    local target_items = items_to_insert
                    local tooltip_msg = "Insert all tracks in this folder"
                    local btn_w = 110
                    
                    if #header_sel_items > 0 and #header_sel_items < #items_to_insert then
                        btn_label = "[+] INSERT SELECTED (" .. #header_sel_items .. ")"
                        target_items = header_sel_items
                        tooltip_msg = "Insert selected tracks"
                        btn_w = 165
                    end
                    
                    local avail_btn_w = r.ImGui_GetContentRegionAvail(ctx)
                    
                    if prefs.enable_randomizer then
                        local rnd_w = 60 
                        local spacing = 4
                        local total_w = btn_w + spacing + rnd_w
                        
                        if avail_btn_w >= total_w then
                            r.ImGui_SetCursorPosX(ctx, (avail_btn_w - total_w) * 0.5)
                            
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.InsertBtnText or 0x66BB6AFF)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0) 
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), c.InsertBtnHover or 0x66BB6A33) 
                            if r.ImGui_Button(ctx, btn_label, btn_w) then ExecuteInsertion(target_items, "Insert Templates: " .. GetCurrentFolderName(), false) end
                            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, tooltip_msg) end
                            r.ImGui_PopStyleColor(ctx, 3)
                            
                            r.ImGui_SameLine(ctx, 0, spacing)
                            
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.FolderText or 0xA0A0A0FF)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFFFFFF11)
                            if r.ImGui_Button(ctx, "[+RND]", rnd_w) then if Core.InsertRandomTemplate(current_view) then missing_file_msg_time = r_time_precise() end end
                            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Insert a Random Track from this folder") end
                            r.ImGui_PopStyleColor(ctx, 3)
                        else
                            r.ImGui_SetCursorPosX(ctx, (avail_btn_w - btn_w) * 0.5)
                            
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.InsertBtnText or 0x66BB6AFF)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0) 
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), c.InsertBtnHover or 0x66BB6A33) 
                            if r.ImGui_Button(ctx, btn_label, btn_w) then ExecuteInsertion(target_items, "Insert Templates: " .. GetCurrentFolderName(), false) end
                            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, tooltip_msg) end
                            r.ImGui_PopStyleColor(ctx, 3)
                            
                            r.ImGui_Spacing(ctx)
                            
                            r.ImGui_SetCursorPosX(ctx, (avail_btn_w - rnd_w) * 0.5)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.FolderText or 0xA0A0A0FF)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFFFFFF11)
                            if r.ImGui_Button(ctx, "[+RND]", rnd_w) then if Core.InsertRandomTemplate(current_view) then missing_file_msg_time = r_time_precise() end end
                            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Insert a Random Track from this folder") end
                            r.ImGui_PopStyleColor(ctx, 3)
                        end
                    else
                        r.ImGui_SetCursorPosX(ctx, (avail_btn_w - btn_w) * 0.5)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.InsertBtnText or 0x66BB6AFF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0) 
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), c.InsertBtnHover or 0x66BB6A33) 
                        if r.ImGui_Button(ctx, btn_label, btn_w) then ExecuteInsertion(target_items, "Insert Templates: " .. GetCurrentFolderName(), false) end
                        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, tooltip_msg) end
                        r.ImGui_PopStyleColor(ctx, 3)
                    end
                    
                elseif search_text ~= "" then
                    if prefs.enable_randomizer then
                        local btn_label = "[+] INSERT RANDOM"
                        local btn_w = 140
                        local avail_btn_w = r.ImGui_GetContentRegionAvail(ctx)
                        r.ImGui_SetCursorPosX(ctx, (avail_btn_w - btn_w) * 0.5)
                        
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.FolderText or 0xA0A0A0FF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0) 
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFFFFFF11) 
                        
                        if r.ImGui_Button(ctx, btn_label, btn_w) then 
                            if Core.InsertRandomTemplate(current_view) then
                                missing_file_msg_time = r_time_precise()
                                if prefs.auto_clear_search then 
                                    search_text = ""
                                    search_box_id = search_box_id + 1
                                    needs_update = true 
                                end
                            end
                        end
                        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Insert a random track from search results") end
                        r.ImGui_PopStyleColor(ctx, 3)
                    end
                end
                
                r.ImGui_Spacing(ctx)
            end
            
            r.ImGui_EndChild(ctx)
        end
        
        if dragging_items and #dragging_items > 0 then
            if r.ImGui_BeginTooltip(ctx) then
                if #dragging_items == 1 then r.ImGui_Text(ctx, "Drop to add track: " .. dragging_items[1].name)
                else r.ImGui_Text(ctx, "Drop to add " .. #dragging_items .. " tracks...") end
                r.ImGui_EndTooltip(ctx)
            end
            
            if r.ImGui_IsMouseReleased(ctx, 0) then
                if not r.ImGui_IsWindowHovered(ctx, r.ImGui_HoveredFlags_AnyWindow() | r.ImGui_HoveredFlags_AllowWhenBlockedByPopup()) then
                    local x, y = r_GetMousePosition()
                    local track = r_GetTrackFromPoint(x, y)
                    if track then r_SetOnlyTrackSelected(track)
                    else
                        local num_tracks = r_CountTracks(0)
                        if num_tracks > 0 then r_SetOnlyTrackSelected(r_GetTrack(0, num_tracks - 1)) end
                    end
                    ExecuteInsertion(dragging_items, "Insert Dragged Templates", true)
                end
                dragging_items = nil
            end
        end

        Core.CheckAndSave(script_path)

        -- ==========================================
        -- PREFERENCES MODAL
        -- ==========================================
        if show_settings_modal then r.ImGui_OpenPopup(ctx, "Preferences"); show_settings_modal = false end

        local modal_w = math.max(150, math.min(300, win_w - 20))
        r.ImGui_SetNextWindowSizeConstraints(ctx, modal_w, 0, 400, 350)
        
        if r.ImGui_BeginPopupModal(ctx, "Preferences", nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
            r.ImGui_TextDisabled(ctx, "General Settings")
            r.ImGui_Spacing(ctx); r.ImGui_Separator(ctx); r.ImGui_Spacing(ctx)

            local rv_fav, new_fav = DrawResponsiveCheckbox(ctx, "Pin favorite tracks to the top", prefs.sort_fav_top, modal_w)
            if rv_fav then
                prefs.sort_fav_top = new_fav
                r_SetExtState("FV_TrackFlow_Prefs", "SortFavTop", new_fav and "1" or "0", true)
                needs_update = true 
            end
            
            local rv_clr, new_clr = DrawResponsiveCheckbox(ctx, "Auto-clear search after insertion", prefs.auto_clear_search, modal_w)
            if rv_clr then
                prefs.auto_clear_search = new_clr
                r_SetExtState("FV_TrackFlow_Prefs", "AutoClear", new_clr and "1" or "0", true)
            end

            local rv_fuz, new_fuz = DrawResponsiveCheckbox(ctx, "Enable Smart Fuzzy Search", prefs.use_fuzzy, modal_w)
            if rv_fuz then
                prefs.use_fuzzy = new_fuz
                r_SetExtState("FV_TrackFlow_Prefs", "UseFuzzy", new_fuz and "1" or "0", true)
                needs_update = true 
            end
            
            local rv_rnd, new_rnd = DrawResponsiveCheckbox(ctx, "Enable Randomizer Features", prefs.enable_randomizer, modal_w)
            if rv_rnd then
                prefs.enable_randomizer = new_rnd
                r_SetExtState("FV_TrackFlow_Prefs", "EnableRandomizer", new_rnd and "1" or "0", true)
                needs_update = true 
            end

            r.ImGui_Spacing(ctx); r.ImGui_Separator(ctx); r.ImGui_Spacing(ctx)
            
            local btn_w = 120
            local child_w = r.ImGui_GetWindowWidth(ctx)
            r.ImGui_SetCursorPosX(ctx, (child_w - btn_w) * 0.5)
            if r.ImGui_Button(ctx, "Close##Prefs", btn_w) then r.ImGui_CloseCurrentPopup(ctx) end
            
            r.ImGui_EndPopup(ctx)
        end

        -- ==========================================
        -- SHORTCUTS MODAL
        -- ==========================================
        if show_shortcuts_modal then r.ImGui_OpenPopup(ctx, "Shortcuts"); show_shortcuts_modal = false end

        local short_w = math.max(250, math.min(350, win_w - 20))
        r.ImGui_SetNextWindowSizeConstraints(ctx, short_w, 0, 400, 500)

        if r.ImGui_BeginPopupModal(ctx, "Shortcuts", nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
            r.ImGui_TextDisabled(ctx, "Keyboard & Mouse Shortcuts")
            r.ImGui_Spacing(ctx); r.ImGui_Separator(ctx); r.ImGui_Spacing(ctx)

            if r.ImGui_BeginTable(ctx, "ShortcutsTable", 2, 0) then
                r.ImGui_TableSetupColumn(ctx, "Key", r.ImGui_TableColumnFlags_WidthFixed(), 75)
                r.ImGui_TableSetupColumn(ctx, "Desc", r.ImGui_TableColumnFlags_WidthStretch())

                local function DrawRow(key, desc)
                    r.ImGui_TableNextRow(ctx)
                    r.ImGui_TableSetColumnIndex(ctx, 0)
                    r.ImGui_TextColored(ctx, 0x66BB6AFF, key) 
                    r.ImGui_TableSetColumnIndex(ctx, 1)
                    r.ImGui_TextWrapped(ctx, desc)
                end

                DrawRow("Enter", "Insert selected track(s)")
                DrawRow("Dbl-Click", "Insert track instantly")
                DrawRow("Up/Down", "Navigate the list")
                DrawRow("Escape", "Clear search / Go back")
                DrawRow("Shift", "Select multiple items")
                DrawRow("Ctrl/Cmd", "Toggle individual item")
                DrawRow("Drag", "Insert at specific location")
                DrawRow("Ctrl+F", "Focus on Search box")
                DrawRow("Ctrl+E", "Open Database Editor")
                DrawRow("Ctrl+T", "Open Theme Settings")

                r.ImGui_EndTable(ctx)
            end

            r.ImGui_Spacing(ctx); r.ImGui_Separator(ctx); r.ImGui_Spacing(ctx)
            
            local btn_w = 120
            local child_w = r.ImGui_GetWindowWidth(ctx)
            r.ImGui_SetCursorPosX(ctx, (child_w - btn_w) * 0.5)
            if r.ImGui_Button(ctx, "Close##Shortcuts", btn_w) then r.ImGui_CloseCurrentPopup(ctx) end
            
            r.ImGui_EndPopup(ctx)
        end
        
    end
    
    r.ImGui_End(ctx) 
  end
  
  PopCustomTheme()
  if open then r.defer(loop) end
end

r.defer(loop)