-- ==========================================
-- FV TrackFlow - Theme Customizer
-- @noindex
-- ==========================================

if not reaper.ImGui_CreateContext then
  reaper.MB("Please install ReaImGui via ReaPack.", "Error", 0)
  return
end

local ctx = reaper.ImGui_CreateContext('FV_Theme_Settings_Ctx')
local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])")
local data_file = script_path .. "theme_data.lua"

local r = reaper

local default_theme = {
    colors = {
        WindowBg       = 0x1A1A1CFF, ChildBg        = 0x1A1A1CFF,
        PopupBg        = 0x141416FF, FrameBg        = 0x25262AFF, 
        FrameBgHovered = 0x303238FF, Text           = 0xDFDFDFFF, 
        Header         = 0x30323800, HeaderHovered  = 0x303238FF, 
        HeaderActive   = 0x40424AFF, Button         = 0x2A2C33FF, 
        ButtonHovered  = 0x3A3D45FF, ButtonActive   = 0x4A4E58FF, 
        Separator      = 0x2A2C33FF, FolderText     = 0xA0A0A0FF, 
        InsertBtnText  = 0x66BB6AFF, InsertBtnHover = 0x66BB6A33,
        AutoTargetText = 0xFFB74DFF,
        QuotesText     = 0x888888FF -- Default muted grey for dark themes
    },
    sizes = { FrameRounding = 4.0, ItemSpacing_Y = 4.0 }
}

local presets = {
    { name = "Studio Dark (Default)", colors = default_theme.colors, sizes = { FrameRounding = 4.0, ItemSpacing_Y = 4.0 } },
    {
        name = "Nordic Clean",
        colors = {
            WindowBg       = 0x2E3440FF, ChildBg        = 0x2E3440FF,
            PopupBg        = 0x242933FF, FrameBg        = 0x3B4252FF, 
            FrameBgHovered = 0x434C5EFF, Text           = 0xD8DEE9FF, 
            Header         = 0x3B425200, HeaderHovered  = 0x434C5EFF, 
            HeaderActive   = 0x4C566AFF, Button         = 0x3B4252FF, 
            ButtonHovered  = 0x434C5EFF, ButtonActive   = 0x4C566AFF, 
            Separator      = 0x434C5EFF, FolderText     = 0x81A1C1FF, 
            InsertBtnText  = 0xA3BE8CFF, InsertBtnHover = 0xA3BE8C33,
            AutoTargetText = 0xD08770FF, QuotesText     = 0x6E7781FF
        },
        sizes = { FrameRounding = 6.0, ItemSpacing_Y = 5.0 }
    },
    {
        name = "Dracula",
        colors = {
            WindowBg       = 0x282A36FF, ChildBg        = 0x282A36FF,
            PopupBg        = 0x1E1F29FF, FrameBg        = 0x44475AFF, 
            FrameBgHovered = 0x6272A4FF, Text           = 0xF8F8F2FF, 
            Header         = 0x44475A00, HeaderHovered  = 0x44475AFF, 
            HeaderActive   = 0x6272A4FF, Button         = 0x44475AFF, 
            ButtonHovered  = 0x6272A4FF, ButtonActive   = 0xFF79C6FF, 
            Separator      = 0x44475AFF, FolderText     = 0x8BE9FDFF, 
            InsertBtnText  = 0x50FA7BFF, InsertBtnHover = 0x50FA7B33,
            AutoTargetText = 0xFFB86CFF, QuotesText     = 0x6272A4FF
        },
        sizes = { FrameRounding = 5.0, ItemSpacing_Y = 4.0 }
    },
    {
        name = "Monokai Pro",
        colors = {
            WindowBg       = 0x2D2A2EFF, ChildBg        = 0x2D2A2EFF,
            PopupBg        = 0x221F22FF, FrameBg        = 0x403E41FF, 
            FrameBgHovered = 0x5B595CFF, Text           = 0xFCFCFAFF, 
            Header         = 0x403E4100, HeaderHovered  = 0x403E41FF, 
            HeaderActive   = 0x5B595CFF, Button         = 0x403E41FF, 
            ButtonHovered  = 0x5B595CFF, ButtonActive   = 0xFFD866FF, 
            Separator      = 0x403E41FF, FolderText     = 0x78DCE8FF, 
            InsertBtnText  = 0xA9DC76FF, InsertBtnHover = 0xA9DC7633,
            AutoTargetText = 0xFC9867FF, QuotesText     = 0x727072FF
        },
        sizes = { FrameRounding = 3.0, ItemSpacing_Y = 5.0 }
    },
    {
        name = "Synthwave '84",
        colors = {
            WindowBg       = 0x262335FF, ChildBg        = 0x262335FF,
            PopupBg        = 0x1D1B28FF, FrameBg        = 0x34294FFF, 
            FrameBgHovered = 0x4F3E75FF, Text           = 0xFFFFFFFF, 
            Header         = 0x34294F00, HeaderHovered  = 0x34294FFF, 
            HeaderActive   = 0x4F3E75FF, Button         = 0x34294FFF, 
            ButtonHovered  = 0x4F3E75FF, ButtonActive   = 0xFF7EDBFF, 
            Separator      = 0x34294FFF, FolderText     = 0x36F9F6FF, 
            InsertBtnText  = 0xFF7EDBFF, InsertBtnHover = 0xFF7EDB33,
            AutoTargetText = 0xF97E72FF, QuotesText     = 0x848bb2FF
        },
        sizes = { FrameRounding = 8.0, ItemSpacing_Y = 6.0 }
    },
    {
        name = "Ableton Mid",
        colors = {
            WindowBg       = 0x898B8CFF, ChildBg        = 0x898B8CFF,
            PopupBg        = 0x9FA1A3FF, FrameBg        = 0xAEB0B2FF, 
            FrameBgHovered = 0xC2C4C6FF, Text           = 0x0A0A0AFF, 
            Header         = 0x898B8C00, HeaderHovered  = 0xA2A4A6FF, 
            HeaderActive   = 0xB5B7B9FF, Button         = 0x9FA1A3FF, 
            ButtonHovered  = 0xB5B7B9FF, ButtonActive   = 0xFF9F20FF, 
            Separator      = 0x6E7072FF, FolderText     = 0x000000FF, 
            InsertBtnText  = 0x0A0A0AFF, InsertBtnHover = 0x0A0A0A22,
            AutoTargetText = 0x992B00FF, 
            QuotesText     = 0x444444FF -- Darker grey for better visibility in light theme
        },
        sizes = { FrameRounding = 0.0, ItemSpacing_Y = 3.0 }
    },
    {
        name = "High Contrast(Dark)",
        colors = {
            WindowBg       = 0x000000FF, ChildBg        = 0x000000FF,
            PopupBg        = 0x0A0A0AFF, FrameBg        = 0x1A1A1AFF, 
            FrameBgHovered = 0x333333FF, Text           = 0xFFFFFFFF, 
            Header         = 0x1A1A1A00, HeaderHovered  = 0x333333FF, 
            HeaderActive   = 0x4D4D4DFF, Button         = 0x1A1A1AFF, 
            ButtonHovered  = 0x333333FF, ButtonActive   = 0x4D4D4DFF, 
            Separator      = 0x333333FF, FolderText     = 0x00E5FFFF, 
            InsertBtnText  = 0x00FF00FF, InsertBtnHover = 0x00FF0033,
            AutoTargetText = 0xFF9800FF, QuotesText     = 0x888888FF
        },
        sizes = { FrameRounding = 0.0, ItemSpacing_Y = 4.0 }
    },
    {
        name = "High Contrast(Light)",
        colors = {
            WindowBg       = 0xF2F2F2FF, ChildBg        = 0xF2F2F2FF,
            PopupBg        = 0xFFFFFFFF, FrameBg        = 0xE0E0E0FF, 
            FrameBgHovered = 0xD0D0D0FF, Text           = 0x000000FF, 
            Header         = 0x30323800, HeaderHovered  = 0xCCCCCCFF, 
            HeaderActive   = 0xBBBBBBFF, Button         = 0xE0E0E0FF, 
            ButtonHovered  = 0xD0D0D0FF, ButtonActive   = 0xC0C0C0FF, 
            Separator      = 0xCCCCCCFF, FolderText     = 0x444444FF, 
            InsertBtnText  = 0x1B5E20FF, InsertBtnHover = 0x1B5E2033,
            AutoTargetText = 0xD84315FF, QuotesText     = 0x555555FF
        },
        sizes = { FrameRounding = 4.0, ItemSpacing_Y = 4.0 }
    }
}

local current_theme = { colors = {}, sizes = {} }

for k, v in pairs(presets[1].colors) do current_theme.colors[k] = v end
for k, v in pairs(presets[1].sizes) do current_theme.sizes[k] = v end

local selected_preset_idx = 0 

if r.file_exists(data_file) then
    local ok, loaded = pcall(dofile, data_file)
    if ok and type(loaded) == "table" then
        if loaded.colors then for k, v in pairs(loaded.colors) do current_theme.colors[k] = v end end
        if loaded.sizes then for k, v in pairs(loaded.sizes) do current_theme.sizes[k] = v end end
    end
end

local color_keys = {
    {"WindowBg", "Main Background"}, {"ChildBg", "List Background"},
    {"PopupBg", "Tooltip/Menu Background"}, {"FrameBg", "Search/Input Box"}, 
    {"FrameBgHovered", "Input Box Hover"}, {"Text", "Main Text Color"}, 
    {"Header", "Selection Background"}, {"HeaderHovered", "Selection Hover"}, 
    {"HeaderActive", "Selected Item Color"}, {"Button", "Buttons"}, 
    {"ButtonHovered", "Button Hover"}, {"ButtonActive", "Button Clicked"}, 
    {"Separator", "Dividers"}, {"FolderText", "Folder Name Color"}, 
    {"InsertBtnText", "Insert Button Text"}, {"InsertBtnHover", "Insert Button Hover"},
    {"AutoTargetText", "Auto-Target Text Color"},
    {"QuotesText", "Quotes Text"} -- New Editor Row
}

local save_status_msg = ""
local save_status_time = 0

local function SaveTheme()
    local file = io.open(data_file, "w")
    if file then
        file:write("-- Auto-generated by FV_TrackFlow_ThemeEditor\nreturn {\n  colors = {\n")
        for k, v in pairs(current_theme.colors) do
            file:write(string.format("    %s = 0x%08X,\n", k, v))
        end
        file:write("  },\n  sizes = {\n")
        for k, v in pairs(current_theme.sizes) do
            if k == "ItemSpacing_Y" or k == "FrameRounding" then
                file:write(string.format("    %s = %.1f,\n", k, v))
            end
        end
        file:write("  }\n}\n")
        file:close()
        
        save_status_msg = "Theme Saved!"
        save_status_time = r.time_precise()
        
        r.SetExtState("FV_TrackFlow", "NeedsReload", "1", false)
    end
end

local function loop()
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x1A1A1CFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), 0x141416FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xDFDFDFFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x2A2C33FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x3A3D45FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x25262AFF)

    r.ImGui_SetNextWindowSize(ctx, 420, 680, r.ImGui_Cond_FirstUseEver())
    
    local window_flags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_AlwaysAutoResize()
    local visible, open = r.ImGui_Begin(ctx, 'Theme Settings (FV TrackFlow)', true, window_flags)
    
    if visible then
        r.ImGui_TextDisabled(ctx, "Color Presets")
        
        local combo_items = { "Custom" }
        for _, p in ipairs(presets) do 
            table.insert(combo_items, p.name) 
        end
        local preset_names = table.concat(combo_items, "\0") .. "\0"
        
        r.ImGui_PushItemWidth(ctx, 250)
        local rv_combo, new_idx = r.ImGui_Combo(ctx, "##ThemeCombo", selected_preset_idx, preset_names)
        if rv_combo then
            selected_preset_idx = new_idx
            if new_idx > 0 then
                local p = presets[new_idx]
                if p then
                    for k, v in pairs(p.colors) do current_theme.colors[k] = v end
                    for k, v in pairs(p.sizes) do current_theme.sizes[k] = v end
                end
            end
        end
        r.ImGui_PopItemWidth(ctx)
        
        r.ImGui_Spacing(ctx); r.ImGui_Separator(ctx); r.ImGui_Spacing(ctx)
        
        r.ImGui_TextDisabled(ctx, "UI Layout & Spacing")
        
        r.ImGui_PushItemWidth(ctx, 200)
        local rv1, nv1 = r.ImGui_SliderDouble(ctx, "Corner Roundness", current_theme.sizes.FrameRounding, 0.0, 12.0, "%.1f")
        if rv1 then current_theme.sizes.FrameRounding = nv1; selected_preset_idx = 0 end
        
        local rv3, nv3 = r.ImGui_SliderDouble(ctx, "Row Vertical Padding", current_theme.sizes.ItemSpacing_Y, 0.0, 10.0, "%.1f")
        if rv3 then current_theme.sizes.ItemSpacing_Y = nv3; selected_preset_idx = 0 end
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_Spacing(ctx); r.ImGui_Separator(ctx); r.ImGui_Spacing(ctx)
        
        r.ImGui_TextDisabled(ctx, "Custom Color Palette")
        local c_flags = r.ImGui_ColorEditFlags_NoInputs() | r.ImGui_ColorEditFlags_AlphaPreviewHalf()
        
        for _, c in ipairs(color_keys) do
            local key, label = c[1], c[2]
            local rv, new_col = r.ImGui_ColorEdit4(ctx, label, current_theme.colors[key], c_flags)
            if rv then current_theme.colors[key] = new_col; selected_preset_idx = 0 end
        end
        
        r.ImGui_Spacing(ctx); r.ImGui_Separator(ctx); r.ImGui_Spacing(ctx)
        
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x1E88E5FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x42A5F5FF)
        if r.ImGui_Button(ctx, "SAVE & APPLY THEME", 160) then SaveTheme() end
        r.ImGui_PopStyleColor(ctx, 2)
        
        if (r.time_precise() - save_status_time) < 3.0 then
            r.ImGui_SameLine(ctx)
            r.ImGui_TextColored(ctx, 0x4CAF50FF, save_status_msg)
        end
    end
    
    r.ImGui_End(ctx)
    r.ImGui_PopStyleColor(ctx, 6)
    
    if open then r.defer(loop) end
end

r.defer(loop)