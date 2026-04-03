-- @description FV TrackFlow
-- @author frioventus
-- @version 0.9.3
-- @category Track Template Manager
-- @provides
--   [main] FV_TrackFlow_Editor.lua
--   [main] FV_TrackFlow_ThemeEditor.lua
--   [nomain] FV_TrackFlow_Core.lua
-- @about A minimalist, keyboard-focused Track Template Manager for REAPER.

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
local is_db_empty = not is_db_loaded or (#Core.track_templates == 0)

local Theme = { colors = {}, sizes = {} }
local theme_data_file = script_path .. "theme_data.lua"
if reaper.file_exists(theme_data_file) then
    local ok, loaded = pcall(dofile, theme_data_file)
    if ok and type(loaded) == "table" then Theme = loaded end
end

-- ==========================================
-- ILHAM VERICI SOZLER (MOTIVATIONAL QUOTES)
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
math.randomseed(math.floor(reaper.time_precise() * 1000))
local current_quote = quotes[math.random(1, #quotes)]

local nav_path = {}
local search_text = ""
local last_search_text = ""
local last_nav_path_str = ""

local current_view = {}
local needs_update = true

local dragging_items = nil 
local kb_selection_idx = 0 
local selected_indices = {} 
local scroll_to_selection = false
local auto_select_first = false 

local missing_file_msg_time = 0 
local force_dock = nil

-- SIHIRLI KOMUT CALISTIRICI (Diger scriptleri tetikler)
local function RunScript(file_name)
    local spath = script_path .. file_name
    if reaper.file_exists(spath) then
        local cmd_id = reaper.AddRemoveReaScript(true, 0, spath, true)
        if cmd_id ~= 0 then reaper.Main_OnCommand(cmd_id, 0) end
    end
end

local function PushCustomTheme()
    local c = Theme.colors or {}
    local popup_bg = c.PopupBg or c.WindowBg or 0x1A1A1CFF
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), c.WindowBg or 0x1A1A1CFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), c.ChildBg or 0x1A1A1CFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), popup_bg)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), c.FrameBg or 0x25262AFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), c.FrameBgHovered or 0x303238FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), c.Text or 0xDFDFDFFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), c.Header or 0x30323800) 
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), c.HeaderHovered or 0x303238FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), c.HeaderActive or 0x40424AFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), c.Button or 0x2A2C33FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), c.ButtonHovered or 0x3A3D45FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), c.ButtonActive or 0x4A4E58FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), c.Separator or 0x2A2C33FF) 
    
    local s = Theme.sizes or {}
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowBorderSize(), 0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), s.FrameRounding or 4)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), s.ItemSpacing_X or 4, s.ItemSpacing_Y or 4)
end

local function PopCustomTheme()
    reaper.ImGui_PopStyleColor(ctx, 13)
    reaper.ImGui_PopStyleVar(ctx, 3)
end

local function DrawMicroBadge(tag)
    local color = Core.GetTagColor(tag) 
    local short_name = Core.GetTagShortName(tag)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x111111FF)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 3)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 5, 0)
    reaper.ImGui_Button(ctx, short_name)
    reaper.ImGui_PopStyleVar(ctx, 2)
    reaper.ImGui_PopStyleColor(ctx, 4)
end

local function loop()
  if reaper.HasExtState("FV_TrackFlow", "NeedsReload") then
      reaper.DeleteExtState("FV_TrackFlow", "NeedsReload", true)
      is_db_loaded = Core.Init(script_path)
      is_db_empty = not is_db_loaded or (#Core.track_templates == 0)
      needs_update = true
  end

  PushCustomTheme()
  reaper.ImGui_SetNextWindowSize(ctx, 350, 500, reaper.ImGui_Cond_FirstUseEver())
  
  if force_dock ~= nil then
      reaper.ImGui_SetNextWindowDockID(ctx, force_dock)
      force_dock = nil
  end
  
  local visible, open = reaper.ImGui_Begin(ctx, 'FV TrackFlow', true, reaper.ImGui_WindowFlags_NoCollapse())
  
  if visible then
    local is_main_window_docked = reaper.ImGui_IsWindowDocked(ctx)
    local current_dock_id = reaper.ImGui_GetWindowDockID(ctx)

    if is_main_window_docked and current_dock_id ~= 0 then
        reaper.SetExtState("FV_TrackFlow", "LastDockID", tostring(current_dock_id), true)
    end

    if reaper.ImGui_BeginPopupContextWindow(ctx, "FV_ContextMenu", 1) then
        if reaper.ImGui_MenuItem(ctx, "Open Database Editor") then RunScript("FV_TrackFlow_Editor.lua") end
        if reaper.ImGui_MenuItem(ctx, "Open Theme Customizer") then RunScript("FV_TrackFlow_ThemeEditor.lua") end
        reaper.ImGui_Separator(ctx)
        
        if reaper.ImGui_MenuItem(ctx, is_main_window_docked and "Undock Window" or "Dock Window") then
            if is_main_window_docked then
                force_dock = 0
            else
                local last_dock = tonumber(reaper.GetExtState("FV_TrackFlow", "LastDockID"))
                if last_dock and last_dock ~= 0 then
                    force_dock = last_dock 
                else
                    force_dock = 2 
                end
            end
        end
        reaper.ImGui_EndPopup(ctx)
    end

    if is_db_empty then
        local win_w = reaper.ImGui_GetWindowWidth(ctx)
        local win_h = reaper.ImGui_GetWindowHeight(ctx)
        
        reaper.ImGui_SetCursorPosY(ctx, (win_h - 150) * 0.5)
        
        local title = "Welcome to FV TrackFlow 🌊"
        local t_w = reaper.ImGui_CalcTextSize(ctx, title)
        reaper.ImGui_SetCursorPosX(ctx, (win_w - t_w) * 0.5)
        reaper.ImGui_Text(ctx, title)
        
        reaper.ImGui_Spacing(ctx)
        
        local msg = "Your database is empty or missing."
        local msg2 = "Right-Click anywhere for options."
        local m_w = reaper.ImGui_CalcTextSize(ctx, msg)
        local m2_w = reaper.ImGui_CalcTextSize(ctx, msg2)
        
        reaper.ImGui_SetCursorPosX(ctx, (win_w - m_w) * 0.5)
        reaper.ImGui_TextDisabled(ctx, msg)
        reaper.ImGui_SetCursorPosX(ctx, (win_w - m2_w) * 0.5)
        reaper.ImGui_TextDisabled(ctx, msg2)
        
        reaper.ImGui_Spacing(ctx); reaper.ImGui_Spacing(ctx); reaper.ImGui_Spacing(ctx)
        
        local btn_label = "Open Database Editor"
        local btn_w = 200
        reaper.ImGui_SetCursorPosX(ctx, (win_w - btn_w) * 0.5)
        
        local c = Theme.colors or {}
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), c.HeaderActive or 0x40424AFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), c.ButtonHovered or 0x3A3D45FF)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 6)
        
        if reaper.ImGui_Button(ctx, btn_label, btn_w, 35) then
            RunScript("FV_TrackFlow_Editor.lua")
        end
        
        reaper.ImGui_PopStyleVar(ctx)
        reaper.ImGui_PopStyleColor(ctx, 2)
        
    else
        local win_w = reaper.ImGui_GetWindowWidth(ctx)
        local current_nav_str = table.concat(nav_path, "/")
        
        if search_text ~= last_search_text or current_nav_str ~= last_nav_path_str or needs_update then
            current_view = Core.UpdateCache(search_text, nav_path)
            last_search_text = search_text
            last_nav_path_str = current_nav_str
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

        local is_ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super())
        local is_shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
        local force_focus_search = false
        if reaper.ImGui_IsWindowAppearing(ctx) then force_focus_search = true end
        
        if reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_RootAndChildWindows()) then
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
                if search_text ~= "" then 
                    search_text = ""
                    auto_select_first = true 
                    needs_update = true
                elseif #nav_path > 0 then 
                    table.remove(nav_path)
                    auto_select_first = true 
                    needs_update = true 
                end
            end
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow()) then
                kb_selection_idx = kb_selection_idx + 1
                if kb_selection_idx > #current_view then kb_selection_idx = #current_view end
                selected_indices = {[kb_selection_idx] = true} 
                scroll_to_selection = true
                force_focus_search = true 
            end
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow()) then
                kb_selection_idx = kb_selection_idx - 1
                if kb_selection_idx < 1 then kb_selection_idx = 1 end
                if #current_view == 0 then kb_selection_idx = 0 end
                selected_indices = {[kb_selection_idx] = true} 
                scroll_to_selection = true
                force_focus_search = true
            end
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) then
                local sel_count = 0
                for k, v in pairs(selected_indices) do if v then sel_count = sel_count + 1 end end
                
                if sel_count > 1 then
                    local items = {}
                    for idx, row in ipairs(current_view) do
                        if selected_indices[idx] and row.type == "item" and not row.data.is_missing then table.insert(items, row.data) end
                    end
                    if #items > 0 then 
                        if Core.InsertTrackTemplateList(items, "Insert Selected Templates", false) then
                            missing_file_msg_time = reaper.time_precise()
                        end
                    end
                elseif kb_selection_idx > 0 and current_view[kb_selection_idx] then
                    local row = current_view[kb_selection_idx]
                    if row.type == "folder" then
                        table.insert(nav_path, row.name)
                        auto_select_first = true 
                        needs_update = true
                    elseif not row.data.is_missing then
                        if Core.InsertTrackTemplate(row.data, false) then
                            missing_file_msg_time = reaper.time_precise()
                        end
                    end
                end
            end
        end

        local show_x = search_text ~= ""
        local show_home = search_text == "" and #nav_path > 0
        local right_space = (show_x or show_home) and -30 or -1

        -- YENİ VE KUSURSUZ AUTO-COMPLETE MANTIĞI
        local autocomplete_suggestion = ""
        local full_autocomplete_tag = ""
        local prefix_to_replace = ""
        local autocomplete_color = 0x888888FF
        
        -- Eğer metnin sonunda boşluk yoksa (kelime yazımı bitmemişse) öneri oluştur
        if search_text ~= "" and not string.match(search_text, "%s$") then
            local search_lower = string.lower(search_text)
            local tags = Core.GetAllTags()
            
            local best_match_len = 0
            for _, tag in ipairs(tags) do
                local tag_lower = string.lower(tag)
                
                -- Metnin son kısmının (suffix) bir tag ile eşleşip eşleşmediğini bul
                for i = 1, #search_lower do
                    local search_suffix = string.sub(search_lower, i)
                    -- Eğer tag bu suffix ile başlıyorsa
                    if string.sub(tag_lower, 1, #search_suffix) == search_suffix then
                        -- Bu suffix'ten önceki karakter boşluk mu kontrol et (ya da kelimenin başı mı)
                        local before_char = ""
                        if i > 1 then before_char = string.sub(search_lower, i - 1, i - 1) end
                        
                        if before_char == "" or string.match(before_char, "%s") then
                            if #search_suffix > best_match_len and #search_suffix < #tag_lower then
                                best_match_len = #search_suffix
                                autocomplete_suggestion = string.sub(tag, #search_suffix + 1)
                                full_autocomplete_tag = tag
                                prefix_to_replace = string.sub(search_text, i)
                                autocomplete_color = Core.GetTagColor(tag)
                            end
                        end
                    end
                end
            end
        end

        if force_focus_search then reaper.ImGui_SetKeyboardFocusHere(ctx) end

        reaper.ImGui_PushItemWidth(ctx, right_space)
        local input_min_x, input_min_y = reaper.ImGui_GetCursorScreenPos(ctx)
        
        -- Tab tuşunun çalışmasına (focus atlamasına) izin veriyoruz, flag YOK.
        local changed, new_search = reaper.ImGui_InputTextWithHint(ctx, '##Search', 'Search or type tags...', search_text)
        local is_input_active = reaper.ImGui_IsItemActive(ctx)
        local is_input_deactivated = reaper.ImGui_IsItemDeactivated(ctx)
        reaper.ImGui_PopItemWidth(ctx)

        if changed then 
            search_text = new_search 
            needs_update = true -- BU SATIR ARTIK ANINDA UPDATE VE RENKLİ ROZET SAĞLIYOR!
        end

        -- KUSURSUZ TAB YAKALAYICI (Focus kaybı anında)
        if is_input_deactivated and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Tab(), false) and full_autocomplete_tag ~= "" then
            local prefix_start = #search_text - #prefix_to_replace
            local base_str = string.sub(search_text, 1, prefix_start)
            
            search_text = base_str .. full_autocomplete_tag .. " "
            needs_update = true
            reaper.ImGui_SetKeyboardFocusHere(ctx, -1) -- Odağı saniyesinde arama kutusuna geri kilitle!
            autocomplete_suggestion = ""
        end

        -- GHOST TEXT ÇİZİMİ
        if is_input_active and autocomplete_suggestion ~= "" then
            local text_w = reaper.ImGui_CalcTextSize(ctx, search_text)
            local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
            local ghost_col = (autocomplete_color & 0xFFFFFF00) | 0x00000099
            reaper.ImGui_DrawList_AddText(draw_list, input_min_x + 8 + text_w, input_min_y + 4, ghost_col, autocomplete_suggestion)
        end
        
        if show_x then
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "X", 26) then search_text = ""; needs_update = true end
            if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, "Clear Search") end
        elseif show_home then
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "▲", 26) then nav_path = {}; needs_update = true end
            if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, "Return to Home") end
        end
        
        reaper.ImGui_Spacing(ctx)

        local show_missing_text = (reaper.time_precise() - missing_file_msg_time) < 2.0

        if reaper.ImGui_BeginChild(ctx, "NavHeader", 0, 22, 0) then
            local header_start_x = reaper.ImGui_GetCursorPosX(ctx)
            
            if search_text == "" then
                if #nav_path > 0 then
                    if reaper.ImGui_Button(ctx, "<", 20) then table.remove(nav_path); needs_update = true end
                    if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, "Go Back") end
                    reaper.ImGui_SameLine(ctx)
                    
                    reaper.ImGui_AlignTextToFramePadding(ctx)
                    if show_missing_text then
                        reaper.ImGui_TextColored(ctx, 0xFF5555FF, "File not found.")
                    else
                        local current_folder = nav_path[#nav_path]
                        reaper.ImGui_Text(ctx, current_folder)
                        if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, table.concat(nav_path, " / ")) end
                    end
                else
                    reaper.ImGui_SetCursorPosX(ctx, header_start_x + 4)
                    reaper.ImGui_AlignTextToFramePadding(ctx)
                    
                    if show_missing_text then
                        reaper.ImGui_TextColored(ctx, 0xFF5555FF, "File not found.")
                    else
                        reaper.ImGui_TextDisabled(ctx, current_quote)
                    end
                end
            else
                local search_sel_items = {}
                for i, row in ipairs(current_view) do
                    if selected_indices[i] and row.type == "item" and not row.data.is_missing then
                        table.insert(search_sel_items, row.data)
                    end
                end

                if #search_sel_items > 0 then
                    local btn_label = "[+] INSERT SELECTED (" .. #search_sel_items .. ")"
                    local c = Theme.colors or {}
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), c.InsertBtnText or 0x66BB6AFF)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0) 
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), c.InsertBtnHover or 0x66BB6A33) 
                    
                    reaper.ImGui_SetCursorPosX(ctx, header_start_x + 4)
                    if reaper.ImGui_Button(ctx, btn_label) then
                        if Core.InsertTrackTemplateList(search_sel_items, "Insert From Search", false) then
                            missing_file_msg_time = reaper.time_precise()
                        end
                        selected_indices = {}
                        kb_selection_idx = 0
                    end
                    if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, "Insert selected tracks directly") end
                    
                    reaper.ImGui_PopStyleColor(ctx, 3)
                else
                    -- ANINDA ÇALIŞAN ÇOKLU KELİME ROZET ALGORİTMASI
                    local active_tags = {}
                    local all_tags = Core.GetAllTags()
                    local search_lower = string.lower(search_text)
                    local padded_search = " " .. search_lower .. " "
                    
                    for _, tag in ipairs(all_tags) do
                        local tag_lower = string.lower(tag)
                        local short_lower = string.lower(Core.GetTagShortName(tag))
                        
                        -- Boşluklu tam eşleşme kontrolü (Tam rozetler de artık anında çıkar)
                        if string.find(padded_search, " " .. tag_lower .. " ", 1, true) or
                           string.find(padded_search, " " .. short_lower .. " ", 1, true) then
                            table.insert(active_tags, tag)
                        end
                    end
                    
                    reaper.ImGui_SetCursorPosX(ctx, header_start_x + 4)
                    reaper.ImGui_AlignTextToFramePadding(ctx)
                    if show_missing_text then
                        reaper.ImGui_TextColored(ctx, 0xFF5555FF, "File not found.")
                    elseif #active_tags > 0 then
                        for _, tag in ipairs(active_tags) do
                            DrawMicroBadge(tag)
                            reaper.ImGui_SameLine(ctx, 0, 4)
                        end
                        reaper.ImGui_TextDisabled(ctx, " found " .. #current_view)
                    else
                        reaper.ImGui_TextDisabled(ctx, "Results for: " .. search_text)
                    end
                end
            end
            reaper.ImGui_EndChild(ctx)
        end
        
        local c = Theme.colors or {}
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), c.ButtonHovered or 0x3A3D45FF)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_PopStyleColor(ctx)

        if reaper.ImGui_BeginChild(ctx, "ListArea", 0, 0, 0) then
            local items_to_insert = {}
            local selected_payload = {}
            local any_item_clicked = false 

            for i, row in ipairs(current_view) do
                reaper.ImGui_PushID(ctx, "row_" .. i)
                
                local is_selected = selected_indices[i] == true
                local active_color = c.HeaderActive or 0x40424AFF
                if is_selected then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), active_color) end
                
                local start_pos_x = reaper.ImGui_GetCursorPosX(ctx)
                local start_pos_y = reaper.ImGui_GetCursorPosY(ctx)
                
                if row.type == "folder" then
                    local clicked = reaper.ImGui_Selectable(ctx, "##fld_"..row.name, is_selected)
                    local end_pos_y = reaper.ImGui_GetCursorPosY(ctx)
                    
                    if clicked then 
                        any_item_clicked = true
                        table.insert(nav_path, row.name)
                        auto_select_first = false 
                        needs_update = true
                    end

                    reaper.ImGui_SetCursorPos(ctx, start_pos_x + 4, start_pos_y)
                    local folder_color = c.FolderText or 0xA0A0A0FF
                    reaper.ImGui_TextColored(ctx, folder_color, "+")
                    
                    reaper.ImGui_SetCursorPos(ctx, start_pos_x + 24, start_pos_y) 
                    reaper.ImGui_TextColored(ctx, folder_color, row.name)
                    
                    reaper.ImGui_SetCursorPosY(ctx, end_pos_y)
                    
                    if is_selected and scroll_to_selection then 
                        reaper.ImGui_SetScrollHereY(ctx, 0.5)
                        scroll_to_selection = false 
                    end
                    reaper.ImGui_Separator(ctx)
                    
                elseif row.type == "item" then
                    local item = row.data
                    
                    local sel_flags = reaper.ImGui_SelectableFlags_AllowDoubleClick()
                    if item.is_missing then sel_flags = sel_flags | reaper.ImGui_SelectableFlags_Disabled() end

                    if not item.is_missing then table.insert(items_to_insert, item) end
                    if is_selected and not item.is_missing then table.insert(selected_payload, item) end
                    
                    local clicked = reaper.ImGui_Selectable(ctx, "##sel_"..item.id, is_selected, sel_flags)
                    local item_hovered = reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_RectOnly())
                    local end_pos_y = reaper.ImGui_GetCursorPosY(ctx)
                    
                    if clicked and not item.is_missing then
                        any_item_clicked = true
                        if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                            if Core.InsertTrackTemplate(item, false) then
                                missing_file_msg_time = reaper.time_precise()
                            end
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
                        reaper.ImGui_SetScrollHereY(ctx, 0.5)
                        scroll_to_selection = false 
                    end
                    
                    if reaper.ImGui_IsItemActive(ctx) and reaper.ImGui_IsMouseDragging(ctx, 0) and not item.is_missing then
                        if not selected_indices[i] then
                            selected_indices = {[i] = true}
                            kb_selection_idx = i
                        end
                        if not dragging_items then
                            dragging_items = {}
                            for idx, r in ipairs(current_view) do
                                if selected_indices[idx] and r.type == "item" and not r.data.is_missing then
                                    table.insert(dragging_items, r.data)
                                end
                            end
                        end
                    end
                    
                    if item_hovered and not dragging_items then
                        if item.is_missing then
                            if reaper.ImGui_BeginTooltip(ctx) then
                                reaper.ImGui_TextColored(ctx, 0xFF5555FF, "File is missing from disk!")
                                reaper.ImGui_EndTooltip(ctx)
                            end
                        else
                            if reaper.ImGui_BeginTooltip(ctx) then
                                reaper.ImGui_Text(ctx, "Double-click, Enter or Drag to add.")
                                if item.target_folder and item.target_folder ~= "" then
                                    reaper.ImGui_TextColored(ctx, 0xFFB74DFF, "Auto-Target: [ " .. item.target_folder .. " ]")
                                end
                                if item.tags and #item.tags > 0 then
                                    reaper.ImGui_Separator(ctx)
                                    for _, tag in ipairs(item.tags) do
                                        DrawMicroBadge(tag)
                                        reaper.ImGui_SameLine(ctx, 0, 4)
                                    end
                                end
                                reaper.ImGui_EndTooltip(ctx)
                            end
                        end
                    end
                    
                    if item_hovered and not item.is_missing then
                        reaper.ImGui_SetCursorPos(ctx, start_pos_x + 4, start_pos_y)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x777777FF)
                        reaper.ImGui_Text(ctx, "☆")
                        reaper.ImGui_PopStyleColor(ctx)
                    end

                    reaper.ImGui_SetCursorPos(ctx, start_pos_x + 24, start_pos_y)
                    if item.is_missing then
                        reaper.ImGui_TextColored(ctx, 0xFF5555FF, "[!] " .. item.display_name)
                    else
                        reaper.ImGui_Text(ctx, item.display_name)
                    end
                    
                    reaper.ImGui_SetCursorPosY(ctx, end_pos_y)
                    reaper.ImGui_Separator(ctx)
                end
                
                if is_selected then reaper.ImGui_PopStyleColor(ctx) end
                reaper.ImGui_PopID(ctx)
            end

            if reaper.ImGui_IsWindowHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 0) and not any_item_clicked then
                if not reaper.ImGui_IsAnyItemHovered(ctx) then
                    kb_selection_idx = 0
                    selected_indices = {}
                end
            end

            if not needs_update and search_text == "" and #nav_path > 0 and #items_to_insert > 0 then
                reaper.ImGui_Spacing(ctx)
                
                local btn_label = "[+] INSERT ALL"
                local target_items = items_to_insert
                local tooltip_msg = "Insert all tracks in this folder"
                local btn_w = 110
                
                if #selected_payload > 0 and #selected_payload < #items_to_insert then
                    btn_label = "[+] INSERT SELECTED (" .. #selected_payload .. ")"
                    target_items = selected_payload
                    tooltip_msg = "Insert selected tracks"
                    btn_w = 165
                end
                
                local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
                reaper.ImGui_SetCursorPosX(ctx, (avail_w - btn_w) * 0.5)
                
                local text_col = c.InsertBtnText or 0x66BB6AFF
                local hover_col = c.InsertBtnHover or 0x66BB6A33
                
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), text_col)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0) 
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), hover_col) 
                
                if reaper.ImGui_Button(ctx, btn_label, btn_w) then
                    if Core.InsertTrackTemplateList(target_items, "Insert Templates: " .. nav_path[#nav_path], false) then
                        missing_file_msg_time = reaper.time_precise()
                    end
                    selected_indices = {} 
                    kb_selection_idx = 0
                end
                if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, tooltip_msg) end
                
                reaper.ImGui_PopStyleColor(ctx, 3)
                reaper.ImGui_Spacing(ctx)
            end
            
            reaper.ImGui_EndChild(ctx)
        end
        
        if dragging_items and #dragging_items > 0 then
            if reaper.ImGui_BeginTooltip(ctx) then
                if #dragging_items == 1 then
                    reaper.ImGui_Text(ctx, "Drop to add track: " .. dragging_items[1].display_name)
                else
                    reaper.ImGui_Text(ctx, "Drop to add " .. #dragging_items .. " tracks...")
                end
                reaper.ImGui_EndTooltip(ctx)
            end
            
            if reaper.ImGui_IsMouseReleased(ctx, 0) then
                if not reaper.ImGui_IsWindowHovered(ctx, reaper.ImGui_HoveredFlags_AnyWindow() | reaper.ImGui_HoveredFlags_AllowWhenBlockedByPopup()) then
                    local x, y = reaper.GetMousePosition()
                    local track = reaper.GetTrackFromPoint(x, y)
                    if track then reaper.SetOnlyTrackSelected(track)
                    else
                        local num_tracks = reaper.CountTracks(0)
                        if num_tracks > 0 then reaper.SetOnlyTrackSelected(reaper.GetTrack(0, num_tracks - 1)) end
                    end
                    
                    if Core.InsertTrackTemplateList(dragging_items, "Insert Dragged Templates", true) then
                        missing_file_msg_time = reaper.time_precise()
                    end
                    selected_indices = {} 
                    kb_selection_idx = 0
                end
                dragging_items = nil
            end
        end
    end
    
    reaper.ImGui_End(ctx) 
  end
  
  PopCustomTheme()
  if open then reaper.defer(loop) end
end

reaper.defer(loop)