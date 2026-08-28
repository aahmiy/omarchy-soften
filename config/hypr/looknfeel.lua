-- soften — look'n'feel.
--
-- Loaded after Omarchy's defaults *and* after the active theme's hyprland.lua,
-- so every value set here wins no matter which theme is applied. That is
-- deliberate: the look is a property of the system, not of a theme.

hl.config({
  general = {
    -- No window frame at all. The focused window is told apart by depth
    -- (shadow), never by a colored outline.
    border_size = 0,

    -- Even, quiet breathing room.
    gaps_in = 4,
    gaps_out = 8,

    -- With no visible frame there is nothing to grab, so lean on Hyprland's
    -- invisible grab area for mouse resizing instead.
    resize_on_border = false,
    extend_border_grab_area = 15,
  },

  decoration = {
    -- The system-wide corner radius. The Omarchy shell reads this back with
    -- `hyprctl getoption decoration:rounding`, so bar popups, notifications,
    -- the menu, the polkit prompt and the lock screen all round to match.
    -- Change this one number and the whole desktop follows.
    rounding = 12,
    -- 2.0 is a plain circular corner; higher bends it towards a squircle.
    rounding_power = 3.0,

    -- Neutral depth in place of the theme's tinted outline.
    shadow = {
      enabled = true,
      range = 22,
      render_power = 3,
      offset = "0 6",
      scale = 1.0,
      color = "rgba(0000004d)",
      color_inactive = "rgba(00000026)",
    },

    -- Frosts anything translucent: the bar strip, shell popups, and the
    -- slight window opacity Omarchy already applies.
    blur = {
      enabled = true,
      size = 6,
      passes = 2,
      new_optimizations = true,
      ignore_opacity = true,
      noise = 0.015,
      contrast = 1.0,
      brightness = 1.0,
      vibrancy = 0.15,
      popups = true,
      popups_ignorealpha = 0.2,
    },

    dim_inactive = false,
  },
})

-- ----------------------------------------------------------------- motion
--
-- Three curves for the whole desktop. `out` decelerates hard and is what
-- almost everything uses on the way in; `soft` is a gentler version for
-- things leaving the screen, which should not snatch attention; `inout`
-- is symmetric, for movement between two known positions.
--
-- `speed` is duration in hundredths of a second, so higher is slower.
-- Nothing here runs past ~220ms. The point is that a window never appears
-- out of nowhere — not that you get to watch it arrive.

hl.curve("softenOut", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.curve("softenGentle", { type = "bezier", points = { { 0.33, 1 }, { 0.68, 1 } } })
hl.curve("softenInOut", { type = "bezier", points = { { 0.65, 0 }, { 0.35, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 2, bezier = "softenOut" })

-- Windows grow in from 94% rather than snapping, and shrink back out a touch
-- faster than they arrived. 210ms in, 130ms out: enough to read as motion,
-- not enough to wait for.
hl.animation({ leaf = "windows", enabled = true, speed = 2.1, bezier = "softenOut" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 2.1, bezier = "softenOut", style = "popin 94%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.3, bezier = "softenGentle", style = "popin 96%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 2.0, bezier = "softenInOut" })

-- No border to animate any more.
hl.animation({ leaf = "border", enabled = false })
hl.animation({ leaf = "borderangle", enabled = false })

hl.animation({ leaf = "fade", enabled = true, speed = 1.6, bezier = "softenGentle" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.2, bezier = "softenGentle" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.0, bezier = "softenGentle" })
hl.animation({ leaf = "fadeSwitch", enabled = false })

hl.animation({ leaf = "layers", enabled = true, speed = 1.7, bezier = "softenOut" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 1.7, bezier = "softenOut", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.2, bezier = "softenGentle", style = "fade" })

-- Omarchy ships workspace switching unanimated. A short slide with a fade
-- gives the switch a direction without costing time.
hl.animation({ leaf = "workspaces", enabled = true, speed = 2.2, bezier = "softenInOut", style = "slidefade 15%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 2.0, bezier = "softenOut", style = "slidevert" })

-- ------------------------------------------------------------------ glass
--
-- The translucency itself is set in ~/.config/omarchy/shell.toml; these
-- rules are what turn it into frost.

hl.layer_rule({ match = { namespace = "^omarchy-bar$" }, blur = true, ignore_alpha = 0.05 })
hl.layer_rule({
  match = {
    namespace = "^omarchy-(menu|notifications|osd|polkit|clipboard|emojis|reminders|keyboard-panel|network-qr)$",
  },
  blur = true,
  ignore_alpha = 0.05,
})
