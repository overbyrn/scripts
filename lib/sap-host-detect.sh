sap_host_detect() {
    local base_dir="${1:-/usr/sap}"
    local sid_dirs sid sid_dir
    local valid_found=0

    # Must have /usr/sap
    [[ -d "$base_dir" ]] || return 1

    # Find SID dirs (3-char)
    mapfile -t sid_dirs < <(
        find "$base_dir" -mindepth 1 -maxdepth 1 -type d \
        -name '[A-Z0-9][A-Z0-9][A-Z0-9]' 2>/dev/null
    )

    [[ ${#sid_dirs[@]} -eq 0 ]] && return 1

    for sid_dir in "${sid_dirs[@]}"; do
        sid="$(basename "$sid_dir")"

        local score=0

        # Signal 1: profile exists and not empty (strongest)
        if compgen -G "$sid_dir/SYS/profile/*" > /dev/null 2>&1; then
            ((score+=2))
        fi

        # Signal 2: exe dir exists
        if [[ -d "$sid_dir/SYS/exe" || -d "$sid_dir/SYS/exe/run" ]]; then
            ((score+=1))
        fi

        # Signal 3: sapservices references SID
        if [[ -r "$base_dir/sapservices" ]] && \
           grep -Eq "(^|[[:space:]/_-])${sid}([[:space:]/_-]|$)" \
               "$base_dir/sapservices" 2>/dev/null; then
            ((score+=1))
        fi

        # Signal 4: sidadm user exists
        if id -u "${sid,,}adm" >/dev/null 2>&1; then
            ((score+=1))
        fi

        # Signal 5: instance dirs exist
        if find "$sid_dir" -maxdepth 1 -type d \
            \( -name 'D[0-9][0-9]' -o -name 'DVEBMGS[0-9][0-9]' \
               -o -name 'J[0-9][0-9]' -o -name 'HDB[0-9][0-9]' \
               -o -name 'ASCS[0-9][0-9]' -o -name 'SCS[0-9][0-9]' \
               -o -name 'ERS[0-9][0-9]' \) \
            | grep -q .; then
            ((score+=1))
        fi

        # Validation threshold
        if (( score >= 3 )); then
            valid_found=1
            break
        fi
    done

    [[ "$valid_found" -eq 1 ]]
}
