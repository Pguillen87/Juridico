#!/usr/bin/env bash

# The Supabase CLI is executed both by native Windows shells and by Bash
# environments. Native Windows binaries cannot resolve POSIX paths such as
# /mnt/c/App/Juridico, while the Ubuntu CI runner must keep its POSIX paths.
native_cli_path() {
  local input_path="$1"

  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$input_path"
    return
  fi
  if command -v wslpath >/dev/null 2>&1; then
    wslpath -w "$input_path"
    return
  fi
  printf '%s' "$input_path"
}

run_supabase_with_native_paths() {
  local -a translated=()
  local previous=''
  local argument

  for argument in "$@"; do
    if [[ "$previous" == '--workdir' || "$previous" == '--file' ]]; then
      translated+=("$(native_cli_path "$argument")")
    else
      translated+=("$argument")
    fi
    previous="$argument"
  done

  "${CLI[@]}" "${translated[@]}"
}

run_supabase_read_with_native_paths() {
  local attempt

  for attempt in 1 2 3 4 5; do
    if run_supabase_with_native_paths "$@"; then
      return 0
    fi
    sleep 2
  done
  return 1
}

wait_for_supabase_readiness() {
  local workdir="$1"
  local attempt

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if run_supabase_with_native_paths db query --local --workdir "$workdir" 'select 1;' >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}
