-- ==========================================
-- FV TrackFlow - Theme Customizer
-- ==========================================
if not reaper.ImGui_CreateContext then
  reaper.MB("Please install ReaImGui via ReaPack.", "Error", 0)
  return
end

local ctx = reaper.ImGui_CreateContext('FV TrackFlow Theme Editor')
local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])")
local data_file = script_path .. "theme_data.lua"

local default_theme = {
    colors = {
        WindowBg       = 0x1A1A1CFF, ChildBg        = 0x1A1A1CFF,
        PopupBg        = 0x141416FF, -- YENI: Tooltip Arka Plani
        FrameBg        = 0x25262AFF, FrameBgHovered = 0x303238FF,
        Text           = 0xDFDFDFFF, Header         = 0x30323800,
        HeaderHovered  = 0x303238FF, HeaderActive   = 0x40424AFF,
        Button         = 0x2A2C33FF, ButtonHovered  = 0x3A3D45FF,
        ButtonActive   = 0x4A4E58FF, Separator      = 0x2A2C33FF,
        FolderText     = 0xA0A0A0FF, InsertBtnText  = 0x66BB6AFF,
        InsertBtnHover = 0x66BB6A33
    },
    sizes = {
        FrameRounding = 4.0, ItemSpacing_X = 4.0, ItemSpacing_Y = 4.0
    }
}

-- PRESET TEMALAR (PopupBg Eklendi)
local presets = {
    ["Dark Theme (Default)"] = default_theme.colors,
    
    ["Midnight Black"] = {
        WindowBg       = 0x0A0A0BFF, ChildBg        = 0x0A0A0BFF,
        PopupBg        = 0x050506FF, -- Tooltip
        FrameBg        = 0x141518FF, FrameBgHovered = 0x1D1E22FF,
        Text           = 0xE0E0E0FF, Header         = 0x1A1B2000,
        HeaderHovered  = 0x1D1E22FF, HeaderActive   = 0x292B33FF,
        Button         = 0x181A1FFF, ButtonHovered  = 0x22242BFF,
        ButtonActive   = 0x2D3039FF, Separator      = 0x1A1B20FF,
        FolderText     = 0x909090FF, InsertBtnText  = 0x4CAF50FF,
        InsertBtnHover = 0x4CAF5033
    },
    
    ["Light Theme"] = {
        WindowBg       = 0xF0F0F0FF, ChildBg        = 0xF0F0F0FF,
        PopupBg        = 0xE8E8E8FF, -- Tooltip
        FrameBg        = 0xE0E0E0FF, FrameBgHovered = 0xD0D0D0FF,
        Text           = 0x222222FF, Header         = 0xDDDDDD00,
        HeaderHovered  = 0xCCCCCCFF, HeaderActive   = 0xAAAAAAFF,
        Button         = 0xDDDDDDFF, ButtonHovered  = 0xCCCCCCFF,
        ButtonActive   = 0xAAAAAAFF, Separator      = 0xCCCCCCFF,
        FolderText     = 0x555555FF, InsertBtnText  = 0x2E7D32FF,
        InsertBtnHover = 0x2E7D3233
    },

    ["Dracula"] = {
        WindowBg       = 0x282A36FF, ChildBg        = 0x282A36FF,
        PopupBg        = 0x1E1F29FF, -- Tooltip
        FrameBg        = 0x44475AFF, FrameBgHovered = 0x6272A4FF,
        Text           = 0xF8F8F2FF, Header         = 0x44475A00,
        HeaderHovered  = 0x44475AFF, HeaderActive   = 0x6272A4FF,
        Button         = 0x44475AFF, ButtonHovered  = 0x6272A4FF,
        ButtonActive   = 0xBD93F9FF, Separator      = 0x44475AFF,
        FolderText     = 0xFF79C6FF, InsertBtnText  = 0x50FA7BFF,
        InsertBtnHover = 0x50FA7B33
    },

    ["Nordic Frost"] = {
        WindowBg       = 0x2E3440FF, ChildBg        = 0x2E3440FF,
        PopupBg        = 0x242933FF, -- Tooltip
        FrameBg        = 0x3B4252FF, FrameBgHovered = 0x434C5EFF,
        Text           = 0xD8DEE9FF, Header         = 0x4C566A00,
        HeaderHovered  = 0x4C566AFF, HeaderActive   = 0x5E81ACFF,
        Button         = 0x434C5EFF, ButtonHovered  = 0x4C566AFF,
        ButtonActive   = 0x5E81ACFF, Separator      = 0x434C5EFF,
        FolderText     = 0x88C0D0FF, InsertBtnText  = 0xA3BE8CFF,
        InsertBtnHover = 0xA3BE8C33
    },

    ["Cyberpunk"] = {
        WindowBg       = 0x0D0D19FF, ChildBg        = 0x0D0D19FF,
        PopupBg        = 0x07070DFF, -- Tooltip
        FrameBg        = 0x1A1A33FF, FrameBgHovered = 0x333366FF,
        Text           = 0x00FFEDFF, Header         = 0x1A1A3300,
        HeaderHovered  = 0x333366FF, HeaderActive   = 0xFF003CFF,
        Button         = 0x1A1A33FF, ButtonHovered  = 0x333366FF,
        ButtonActive   = 0xFF003CFF, Separator      = 0x333366FF,
        FolderText     = 0xFCE205FF, InsertBtnText  = 0xFF003CFF,
        InsertBtnHover = 0xFF003C33
    },

    ["Deep Ocean"] = {
        WindowBg       = 0x0F172AFF, ChildBg        = 0x0F172AFF,
        PopupBg        = 0x0B1121FF, -- Tooltip
        FrameBg        = 0x1E293BFF, FrameBgHovered = 0x334155FF,
        Text           = 0xE2E8F0FF, Header         = 0x1E293B00,
        HeaderHovered  = 0x334155FF, HeaderActive   = 0x0284C7FF,
        Button         = 0x1E293BFF, ButtonHovered  = 0x334155FF,
        ButtonActive   = 0x0284C7FF, Separator      = 0x1E293BFF,
        FolderText     = 0x38BDF8FF, InsertBtnText  = 0x34D399FF,
        InsertBtnHover = 0x34D39933
    }
}

local current_theme = { colors = {}, sizes = {} }

local function LoadTheme()
    if reaper.file_exists(data_file) then
        local ok, t = pcall(dofile, data_file)
        if ok and type(t) == "table" then
            for k, v in pairs(default_theme.colors) do current_theme.colors[k] = t.colors and t.colors[k] or v end
            for k, v in pairs(default_theme.sizes) do current_theme.sizes[k] = t.sizes and t.sizes[k] or v end
            return
        end
    end
    for k, v in pairs(default_theme.colors) do current_theme.colors[k] = v end
    for k, v in pairs(default_theme.sizes) do current_theme.sizes[k] = v end
end

LoadTheme()

local save_msg, save_time = "", 0

local function SaveTheme()
    local f = io.open(data_file, "w")
    if f then
        f:write("-- Auto-generated by FV_TrackFlow_ThemeEditor\nreturn {\n")
        f:write("  colors = {\n")
        for k, v in pairs(current_theme.colors) do f:write(string.format("    %s = 0x%08X,\n", k, v & 0xFFFFFFFF)) end
        f:write("  },\n  sizes = {\n")
        for k, v in pairs(current_theme.sizes) do f:write(string.format("    %s = %.1f,\n", k, v)) end
        f:write("  }\n}\n")
        f:close()
        save_msg = "Theme Saved!"
        save_time = reaper.time_precise()
    end
end

local color_keys = {
    {"WindowBg", "Main Background"}, {"ChildBg", "List Background"},
    {"PopupBg", "Tooltip/Popup Background"}, -- YENI
    {"FrameBg", "Search Bar Background"}, {"FrameBgHovered", "Search Bar Hovered"},
    {"Text", "Main Text Color"}, {"FolderText", "Folder Text Color"},
    {"HeaderHovered", "Selection Highlight (Hover)"}, {"HeaderActive", "Selection Highlight (Active)"},
    {"Button", "Standard Button"}, {"ButtonHovered", "Standard Button Hover"},
    {"ButtonActive", "Standard Button Active"}, {"Separator", "Line Separators"},
    {"InsertBtnText", "[+] ALL Button Text"}, {"InsertBtnHover", "[+] ALL Button Hover"}
}

local selected_preset = "Dark Theme (Default)"

local function loop()
    -- Editor'un kendi temasi
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), 0x1A1A1CFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x1A1A1CFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xDFDFDFFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2A2C33FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x3A3D45FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x25262AFF)
    
    reaper.ImGui_SetNextWindowSize(ctx, 420, 580, reaper.ImGui_Cond_FirstUseEver())
    local visible, open = reaper.ImGui_Begin(ctx, 'FV TrackFlow - Theme Customizer', true)
    
    if visible then
        reaper.ImGui_TextDisabled(ctx, "Customize your FV TrackFlow experience.")
        reaper.ImGui_Spacing(ctx); reaper.ImGui_Separator(ctx); reaper.ImGui_Spacing(ctx)
        
        -- PRESETS MENU
        reaper.ImGui_Text(ctx, "THEME PRESETS")
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_PushItemWidth(ctx, 250)
        if reaper.ImGui_BeginCombo(ctx, "##presets", selected_preset) then
            for preset_name, preset_colors in pairs(presets) do
                if reaper.ImGui_Selectable(ctx, preset_name, selected_preset == preset_name) then
                    selected_preset = preset_name
                    for k, v in pairs(preset_colors) do current_theme.colors[k] = v end
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end
        reaper.ImGui_PopItemWidth(ctx)
        
        reaper.ImGui_Spacing(ctx); reaper.ImGui_Separator(ctx); reaper.ImGui_Spacing(ctx)
        
        -- COLORS
        reaper.ImGui_Text(ctx, "CUSTOM COLORS")
        reaper.ImGui_Spacing(ctx)
        local c_flags = reaper.ImGui_ColorEditFlags_NoInputs() | reaper.ImGui_ColorEditFlags_AlphaBar() | reaper.ImGui_ColorEditFlags_AlphaPreviewHalf()
        
        for _, c in ipairs(color_keys) do
            local key, label = c[1], c[2]
            local rv, new_col = reaper.ImGui_ColorEdit4(ctx, label, current_theme.colors[key], c_flags)
            if rv then current_theme.colors[key] = new_col; selected_preset = "Custom" end
        end
        
        reaper.ImGui_Spacing(ctx); reaper.ImGui_Separator(ctx); reaper.ImGui_Spacing(ctx)
        
        -- SAVE BUTTONS
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x1E88E5FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x42A5F5FF)
        if reaper.ImGui_Button(ctx, "SAVE THEME", 120) then SaveTheme() end
        reaper.ImGui_PopStyleColor(ctx, 2)
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Reset to Default", 120) then
            for k, v in pairs(default_theme.colors) do current_theme.colors[k] = v end
            for k, v in pairs(default_theme.sizes) do current_theme.sizes[k] = v end
            selected_preset = "Dark Theme (Default)"
            SaveTheme()
        end
        
        if (reaper.time_precise() - save_time) < 3.0 then
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_TextColored(ctx, 0x4CAF50FF, save_msg)
        end
        
        reaper.ImGui_End(ctx)
    end
    
    reaper.ImGui_PopStyleColor(ctx, 6)
    if open then reaper.defer(loop) end
end

reaper.defer(loop)
