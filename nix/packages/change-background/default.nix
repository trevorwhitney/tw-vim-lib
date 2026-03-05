{ pkgs, ... }: pkgs.writeShellApplication {
  name = "change-background";

  runtimeInputs = with pkgs; [ tmux ];

  text = ''
    function change_background() {
      local mode_setting="''${1}"
      local mode="light"

      # TODO: should only happen on MacOS
      if [[ ''${#} -eq 0 ]]; then
        if defaults read -g AppleInterfaceStyle; then
          mode="dark"
        fi
      else
        case ''${mode_setting} in
        dark)
          osascript -l JavaScript -e "Application('System Events').appearancePreferences.darkMode = true" >/dev/null
          mode="dark"
          ;;
        *)
          osascript -l JavaScript -e "Application('System Events').appearancePreferences.darkMode = false" >/dev/null
          mode="light"
          ;;
        esac
      fi

      tmux set-environment -g BACKGROUND "''${mode}"
      tmux source-file ~/.config/tmux/tmux.conf

      case "''${mode}" in
      dark)
        tmux set-environment -g BAT_THEME "ansi"
        tmux set-environment -g FZF_PREVIEW_PREVIEW_BAT_THEME "ansi"
        ;;
      *)
        tmux set-environment -g BAT_THEME "ansi"
        tmux set-environment -g FZF_PREVIEW_PREVIEW_BAT_THEME "ansi"
        ;;
      esac
    }

    change_background "''$@"
  '';
}
