# Usage:
#   just clean          # prompts before each step
#   just clean -y       # skips all prompts
#   just clean --yes    # skips all prompts

clean *args:
    #!/usr/bin/env bash
    skip_confirmation=0
    case "{{args}}" in
      *-y*|*--yes*) skip_confirmation=1 ;;
    esac

    confirm() {
      [ "$skip_confirmation" = "1" ] && return 0
      read -r -n 1 -p "$1 [y/N] " ans
      echo
      case "$ans" in
        [yY]) return 0 ;;
        *) return 1 ;;
      esac
    }

    remove() {
      if [ -e "$1" ]; then
        confirm "Remove $1?" && { echo "Removing $1"; rm -rf "$1"; }
      else
        echo "Already removed: $1"
      fi
    }

    if pgrep -x logos > /dev/null; then
      confirm "Kill 'logos' process?" && pkill logos
    else
      echo "Already killed"
    fi

    remove state

    shopt -s nullglob
    timestamp_files=( [0-9]* )
    shopt -u nullglob
    if [ ${#timestamp_files[@]} -gt 0 ]; then
      confirm "Remove ${timestamp_files[*]}?" && { echo "Removing ${timestamp_files[*]}"; rm -rf "${timestamp_files[@]}"; }
    else
      echo "Already removed: [0-9]* (no matching files)"
    fi

    remove keystore.yaml
    remove user_config.yaml

run: (clean "-y")
    nix run
