{ pkgs, ... }: pkgs.writeShellApplication {
  name = "change-background";

  runtimeInputs = with pkgs; [ tmux ];

  text = ''
    function everforest_light() {
      #kitten themes --reload-in=all "Everforest Light Soft"
      tmux set-environment -g ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE "fg=#a6b0a0,bg=#f3ead3"
    }

    function everforest_dark() {
      #kitten themes --reload-in=all "Everforest Dark Soft"
      tmux set-environment -g ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE "fg=#9da9a0,bg=#333c43"

    }

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
        tmux set-environment -g BAT_THEME "Solarized (dark)"
        tmux set-environment -g FZF_PREVIEW_PREVIEW_BAT_THEME "Solarized (dark)"
        sed -i 's/everforest-light/everforest-dark/' "''${XDG_CONFIG_HOME}/k9s/config.yaml"
        everforest_dark
        ;;
      *)
        tmux set-environment -g BAT_THEME "Solarized (light)"
        tmux set-environment -g FZF_PREVIEW_PREVIEW_BAT_THEME "Solarized (light)"
        sed -i 's/everforest-dark/everforest-light/' "''${XDG_CONFIG_HOME}/k9s/config.yaml"
        everforest_light
        ;;
      esac
    }

    change_background "''$@"
  '';
}
