set -Eeuo pipefail
source ./utility.sh
ARG="${1:-}"

if [[ "$ARG" == "--inside-chroot" ]]; then
    source ./chroot.sh
    exit 0
fi

source ./non_chroot.sh
