-- Cursor smear, inside nvim and out.
--
-- Two halves of one decision:
--
--   smear-cursor.nvim     draws the smear inside nvim, in terminal cells
--   kitty's cursor_trail  draws it everywhere else -- the shell, lazygit,
--                         btop -- GPU-side, from ~/.config/kitty/kitty.conf
--
-- Both animate the same physical cursor, so leaving both live means two
-- overlapping trails on every jump, at two different decay rates. The
-- kitty_trail block below gives each one the half of the session it owns:
-- kitty's trail is suppressed for as long as nvim is in the foreground, and
-- comes back the moment nvim exits or is suspended.
--
-- To go the other way instead -- one GPU-side effect everywhere and nothing
-- for nvim to redraw -- set `enabled = false` in setup() below and drop
-- `handoff = true`. kitty's trail works perfectly well inside nvim on its own,
-- and costs no Lua.

local handoff = true

-- kitty has no per-window cursor_trail and no mappable toggle action, so the
-- switch is a config reload with an override stacked on top: `-o
-- cursor_trail=0` suppresses it, `--ignore-overrides` drops back to whatever
-- kitty.conf says. Two caveats, both inherent to that being a global reload:
--
--   * it applies to every kitty window, not only this one, so with two nvims
--     in two windows the first one to exit restores the trail for both;
--   * it re-reads kitty.conf, so a background_opacity nudged at runtime with
--     ctrl+shift+a snaps back to the configured 0.85.
local function kitty_trail(on, blocking)
  local socket = vim.env.KITTY_LISTEN_ON
  if not socket or socket == "" then
    return -- not inside kitty, or allow_remote_control is off
  end

  local kitten = vim.fn.executable("kitten") == 1 and "kitten" or "kitty"
  if vim.fn.executable(kitten) == 0 then
    return
  end

  local cmd = { kitten, "@", "--to", socket, "load-config", "--no-response" }
  if on then
    table.insert(cmd, "--ignore-overrides")
  else
    vim.list_extend(cmd, { "-o", "cursor_trail=0" })
  end

  -- On the way out nvim will not be around to reap an async job, and a trail
  -- left switched off is the one failure that outlives the session, so that
  -- direction waits. --no-response keeps it to a few milliseconds on a local
  -- socket.
  local ok, proc = pcall(vim.system, cmd, { text = true })
  if ok and blocking then
    pcall(proc.wait, proc, 1000)
  end
end

return {
  {
    "https://github.com/sphamba/smear-cursor.nvim",
    config = function()
      require("smear_cursor").setup({
        -- enabled = false,
        cursor_color = "#ffffff",

        never_draw_over_target = true,

        smear_insert_mode = false,
        min_vertical_distance_smear = 2,
        min_horizontal_distance_smear = 2,

        time_interval = 17, -- ms
        stiffness = 0.9,
        trailing_stiffness = 0.4,
        damping = 0.99, -- stops bouncing

        -- anticipation = 0.2,
        -- distance_stop_animating = 0.6,
      })

      if not handoff then
        return
      end

      local group = vim.api.nvim_create_augroup("KittyCursorTrailHandoff", { clear = true })

      -- Suspend/Resume matter as much as Enter/Leave here: ctrl-z back to the
      -- shell is exactly the case where you want the trail again.
      vim.api.nvim_create_autocmd({ "VimEnter", "VimResume" }, {
        group = group,
        desc = "nvim is drawing the smear -- stand kitty's trail down",
        callback = function()
          kitty_trail(false, false)
        end,
      })

      vim.api.nvim_create_autocmd({ "VimLeavePre", "VimSuspend" }, {
        group = group,
        desc = "handing the cursor back to the shell -- restore kitty's trail",
        callback = function()
          kitty_trail(true, true)
        end,
      })
    end,
  },
}
