-- Lenovo Legion Tab Gen 3 (TB321FU) BOE NT36523 DSI panel, 1600x2560.
-- The panel runs at a fixed link clock (its 144 or 165 Hz class, set by the
-- kernel's preferred mode); lower refresh rates extend the vertical front porch
-- (Android dfps_immediate_porch_mode_vfp).

local tb321fu_refresh_rates = {}
for hz = 60, 165 do
    table.insert(tb321fu_refresh_rates, hz)
end

gamescope.config.known_displays.lenovo_tb321fu_boe = {
    pretty_name = "Lenovo Legion Tab Gen 3 BOE",
    dynamic_refresh_rates = tb321fu_refresh_rates,
    dynamic_modegen = function(base_mode, refresh)
        local mode = base_mode

        gamescope.modegen.set_resolution(mode, 1600, 2560)
        -- hfp, hsync, hbp (both DSI links together)
        gamescope.modegen.set_h_timings(mode, 566, 40, 108)
        -- Keep the preferred mode's pixel clock; pick the VFP for the refresh.
        local vtotal = math.floor(mode.clock * 1000 / (mode.htotal * refresh) + 0.5)
        local vfp = vtotal - 2560 - 2 - 258
        if vfp < 30 then
            vfp = 30
        end
        -- vfp, vsync, vbp
        gamescope.modegen.set_v_timings(mode, vfp, 2, 258)
        -- round to nearest: 949666 kHz / (2314 * 2850) = 143.99 Hz is 144 Hz
        mode.vrefresh = math.floor((1000 * mode.clock) / (mode.htotal * mode.vtotal) + 0.5)
        return mode
    end,
    -- No EDID: gamescope synthesizes one and identifies the panel through
    -- GAMESCOPE_INTERNAL_DEVICE_ID (the Armada device id).
    matches = function(display)
        if display.device_id == "lenovo-legion-tab"
            and display.internal and not display.has_edid then
            return 6000
        end
        return -1
    end
}
debug("Registered Lenovo Legion Tab Gen 3 BOE as a known display")
