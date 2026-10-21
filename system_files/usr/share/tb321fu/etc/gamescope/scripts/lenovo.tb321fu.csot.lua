-- Lenovo Legion Tab Gen 3 (TB321FU) CSOT NT36523 DSI panel, 1600x2560.
-- The panel runs at a fixed link clock (its 120 or 165 Hz class, set by the
-- kernel's preferred mode); lower refresh rates extend the vertical front porch
-- (Android dfps_immediate_porch_mode_vfp).

-- Both panels share the Armada device id; tell them apart by the panel node.
local function tb321fu_panel_is(name)
    local f = io.open("/sys/firmware/devicetree/base/soc@0/display-subsystem@ae00000/dsi@ae94000/panel@0/compatible", "r")
    if not f then
        return false
    end
    local compatible = f:read("*a")
    f:close()
    return compatible:find("nt36523-" .. name, 1, true) ~= nil
end

local tb321fu_refresh_rates = {}
for hz = 60, 165 do
    table.insert(tb321fu_refresh_rates, hz)
end

gamescope.config.known_displays.lenovo_tb321fu_csot = {
    pretty_name = "Lenovo Legion Tab Gen 3 CSOT",
    dynamic_refresh_rates = tb321fu_refresh_rates,
    dynamic_modegen = function(base_mode, refresh)
        local mode = base_mode

        gamescope.modegen.set_resolution(mode, 1600, 2560)
        -- hfp, hsync, hbp (both DSI links together)
        gamescope.modegen.set_h_timings(mode, 566, 40, 108)
        -- Keep the preferred mode's pixel clock; pick the VFP for the refresh.
        local vtotal = math.floor(mode.clock * 1000 / (mode.htotal * refresh) + 0.5)
        local vfp = vtotal - 2560 - 4 - 256
        if vfp < 30 then
            vfp = 30
        end
        -- vfp, vsync, vbp
        gamescope.modegen.set_v_timings(mode, vfp, 4, 256)
        -- round to nearest: 791388 kHz / (2314 * 2850) = 119.99 Hz is 120 Hz
        mode.vrefresh = math.floor((1000 * mode.clock) / (mode.htotal * mode.vtotal) + 0.5)
        return mode
    end,
    -- Same specification as the BOE panel per Lenovo PSREF: 98% DCI-P3 (nominal
    -- primaries, not measured), 500 nits typical, 1500:1, HDR10.
    -- An LCD has one global backlight, so the frame average can reach the
    -- peak; the black level follows from the contrast ratio.
    colorimetry = {
        r = { x = 0.6800, y = 0.3200 },
        g = { x = 0.2650, y = 0.6900 },
        b = { x = 0.1500, y = 0.0600 },
        w = { x = 0.3127, y = 0.3290 },
    },
    hdr = {
        supported = true,
        eotf = gamescope.eotf.gamma22,
        max_content_light_level = 500,
        max_frame_average_luminance = 500,
        min_content_light_level = 0.33,
    },
    -- No EDID: gamescope synthesizes one and identifies the panel through
    -- GAMESCOPE_INTERNAL_DEVICE_ID (the Armada device id).
    matches = function(display)
        if display.device_id == "lenovo-legion-tab"
            and display.internal and not display.has_edid
            and tb321fu_panel_is("csot") then
            return 6000
        end
        return -1
    end
}
debug("Registered Lenovo Legion Tab Gen 3 CSOT as a known display")
