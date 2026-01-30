# Colors
NC=$'\e[0m'
RED=$'\e[0;31m'
GREEN=$'\e[0;32m'
YELLOW=$'\e[0;33m'
BLUE=$'\e[0;34m'
MAGENTA=$'\e[0;35m'
CYAN=$'\e[0;36m'
WHITE=$'\e[0;37m'

set_pass() {
	local var="$1"
	local prompt_msg="$2"
	local password password_confirm

	while true; do
		read -rsp "$prompt_msg: " password
		echo
		read -rsp "Confirm password: " password_confirm
		echo
		if [[ "$password" = "$password_confirm" ]]; then
			eval "$var=\"\$password\""
            echo
			break
		else
			msg RED "Passwords don't match."
		fi
	done
}

msg() {
	local color="$1"
	local text="$2"
	local color_code

	case "$color" in
		RED) color_code="$RED" ;;
		GREEN) color_code="$GREEN" ;;
		YELLOW) color_code="$YELLOW" ;;
		BLUE) color_code="$BLUE" ;;
		MAGENTA) color_code="$MAGENTA" ;;
		CYAN) color_code="$CYAN" ;;
		*) color_code="$NC" ;;
	esac

	echo -e "${color_code}${text}${NC}"
}
