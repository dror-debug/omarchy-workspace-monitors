.pragma library

// App glyphs for a workspace chip. Regexes are searched against the window
// class (check classes with `hyprctl clients -j`); first match wins.
// `simple: true` glyphs come from the Simple Icons font, the rest from the
// bar's Nerd Font. Users add their own rules through the widget's
// `iconRules` setting, which is searched before these.
var rules = [
  // Browsers
  { re: /zen/, glyph: "", simple: true },
  { re: /[Ff]irefox/, glyph: "" },
  // Chrome/Chromium PWAs that get their own icon, before the browser catch-all
  { re: /chrome-claude\.ai/, glyph: "", simple: true },
  { re: /chrome-app\.notion\.com/, glyph: "", simple: true },
  { re: /chrome-calendar\.notion\.so/, glyph: "\u{F00ED}" },
  { re: /chrome-gemini\.google\.com/, glyph: "", simple: true },
  // Other web apps (chrome-<host>__… / crx_…) fall through to a generic
  // browser glyph in iconFor().
  { re: /^(chromium|[Gg]oogle-chrome|brave-browser)$/, glyph: "" },

  // Neovim and Omarchy TUIs (launched as org.omarchy.<tool>)
  { re: /org\.omarchy\.nvim|neovim|nvim/, glyph: "" },
  { re: /org\.omarchy\.btop/, glyph: "" },
  { re: /org\.omarchy\.lazygit/, glyph: "" },
  { re: /org\.omarchy\.impala/, glyph: "" },
  { re: /org\.omarchy\.bluetui/, glyph: "" },
  { re: /org\.omarchy\.wiremix/, glyph: "" },

  // Terminals (and any other org.omarchy.* TUI)
  { re: /com\.mitchellh\.ghostty|Alacritty|kitty|foot|footclient|org\.wezfurlong\.wezterm|org\.omarchy\./, glyph: "" },

  // Editors and dev tools
  { re: /[Cc]ode/, glyph: "\u{F0A1E}" },
  { re: /jetbrains-|dev\.zed\.Zed/, glyph: "" },
  { re: /Docker Desktop/, glyph: "" },

  // Chat
  { re: /slack/, glyph: "" },
  { re: /[Dd]iscord/, glyph: "\u{F066F}" },
  { re: /[Ss]ignal/, glyph: "" },
  { re: /WhatsApp/, glyph: "" },
  { re: /[Zz]oom/, glyph: "\u{F0567}" },

  // Notes and productivity
  { re: /[Oo]bsidian/, glyph: "\u{F20C}", simple: true },
  { re: /[Nn]otion/, glyph: "" },
  { re: /[Ff]igma/, glyph: "" },
  { re: /libreoffice/, glyph: "\u{F0219}" },
  { re: /1[Pp]assword/, glyph: "\u{F0306}" },

  // Media
  { re: /[Ss]potify/, glyph: "" },
  { re: /mpv|vlc/, glyph: "" },

  // Files
  { re: /org\.gnome\.Nautilus|nautilus|dolphin|thunar|nemo/, glyph: "" },
  { re: /localsend/, glyph: "" }
]

var fallback = { glyph: "\uF2D0", simple: false }

// `extra` is the widget's iconRules setting:
//   [{ "match": "<regex>", "glyph": "<char>", "font": "Simple Icons", "heart": true }]
// `font` and `heart` are optional; `heart` draws a gear-rimmed heart instead.
function compile(extra) {
  var out = []
  for (var i = 0; i < (extra || []).length; i++) {
    var r = extra[i]
    if (!r || !r.match) continue
    try {
      out.push({ re: new RegExp(r.match), glyph: String(r.glyph || ""), simple: r.font === "Simple Icons", heart: !!r.heart })
    } catch (e) {
      console.warn("workspace-monitors: bad iconRules regex:", r.match)
    }
  }
  return out
}

function iconFor(cls, userRules) {
  for (var j = 0; j < (userRules || []).length; j++) {
    if (userRules[j].re.test(cls)) return userRules[j]
  }
  for (var i = 0; i < rules.length; i++) {
    if (rules[i].re.test(cls)) return rules[i]
  }
  if (/^chrome-|^crx_/.test(cls)) return { glyph: "\uF268" }
  return fallback
}
