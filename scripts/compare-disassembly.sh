#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s failglob
IFS=$'\n\t'

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 2; }

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_directory
readonly normalize_script="${script_directory}/normalize-disassembly.sh"

verbose="false"
name_filter=""
declare -a base_object_files=()
declare -a head_object_files=()
workspace=""

cleanup() {
  if [[ -n "${workspace}" && -d "${workspace}" ]]; then
    rm -rf -- "${workspace}"
  fi
  return 0
}

usage() {
  printf -- 'Usage: %s [--verbose] [--filter <regex>] <base object>... -- <head object>...\n' \
    "$(basename -- "${BASH_SOURCE[0]}")"
  printf -- '  --verbose        print a unified diff of every changed function\n'
  printf -- '  --filter <regex> compare only the functions whose demangled name matches the\n'
  printf -- '                   extended regular expression\n'
  printf -- 'Functions are paired by symbol, and the verdicts describe the head against the base.\n'
  printf -- 'Exits 0 when nothing differs, 1 when anything differs and 2 on errors.\n'
  return 0
}

require_command() {
  local command_name="${1:?require_command requires the name of the command}"

  if ! command -v "${command_name}" > /dev/null 2>&1; then
    fatal "'${command_name}' is required by $(basename -- "${BASH_SOURCE[0]}") but is not installed"
  fi
  return 0
}

parse_arguments() {
  local option
  local separator_found="false"
  while [[ "$#" -gt 0 ]]; do
    option="$1"
    shift
    case "${option}" in
      --verbose)
        verbose="true"
        ;;
      --filter)
        if [[ "$#" -eq 0 || -z "$1" ]]; then
          fatal "--filter requires an extended regular expression to match demangled names"
        fi
        name_filter="$1"
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      --)
        separator_found="true"
        head_object_files=( "$@" )
        break
        ;;
      -*)
        fatal "Unknown argument '${option}'" "$(usage)"
        ;;
      *)
        base_object_files+=( "${option}" )
        ;;
    esac
  done

  if [[ "${separator_found}" != "true" ]]; then
    fatal "Found no '--' between the base and the head object files" "$(usage)"
  fi
  if [[ "${#base_object_files[@]}" -eq 0 ]]; then
    fatal "Found no base object files before '--'" "$(usage)"
  fi
  if [[ "${#head_object_files[@]}" -eq 0 ]]; then
    fatal "Found no head object files after '--'" "$(usage)"
  fi
  return 0
}

normalize_object_files() {
  local side="${1:?normalize_object_files requires the name of the side}"
  local side_number="${2:?normalize_object_files requires the number of the side}"
  local -n side_object_files_ref="${3:?normalize_object_files requires the object file array}"
  local -n listing_files_ref="${4:?normalize_object_files requires the listing file array}"
  local listing_directory="${5:?normalize_object_files requires the listings directory}"
  local manifest_file="${6:?normalize_object_files requires the manifest file}"

  log "Normalizing ${#side_object_files_ref[@]} ${side} object files..."
  if ! mkdir -p -- "${listing_directory}"; then
    fatal "Failed to create the directory '${listing_directory}'"
  fi

  local object_file listing_file
  local object_index=0
  for object_file in "${side_object_files_ref[@]}"; do
    object_index=$(( object_index + 1 ))
    listing_file="${listing_directory}/${object_index}.txt"
    if ! "${normalize_script}" -- "${object_file}" > "${listing_file}"; then
      fatal "Failed to normalize the object file '${object_file}'"
    fi
    listing_files_ref+=( "${listing_file}" )
    if ! printf -- '%s\t%s\t%s\n' "${listing_file}" "${side_number}" "${object_file##*/}" \
      >> "${manifest_file}"; then
      fatal "Failed to add '${listing_file}' to '${manifest_file}'"
    fi
  done
  return 0
}

demangle_symbols() {
  local symbols_file="${1:?demangle_symbols requires the file to write the symbols to}"
  local demangled_file="${2:?demangle_symbols requires the file to write the demangled names to}"
  shift 2
  local -a listing_files=( "$@" )

  local -r labels_file="${symbols_file}.labels"
  if ! sed -n 's|^<\(.*\)>:$|\1|p' "${listing_files[@]}" > "${labels_file}"; then
    fatal "Failed to read the symbols out of the disassembly listings"
  fi
  if ! LC_ALL=C sort -u "${labels_file}" > "${symbols_file}"; then
    fatal "Failed to sort the symbols of the disassembly listings"
  fi
  if ! swift demangle --simplified < "${symbols_file}" > "${demangled_file}"; then
    fatal "Failed to demangle the symbols of the disassembly listings"
  fi

  local symbol_count demangled_count
  symbol_count="$(wc -l < "${symbols_file}" | tr -d '[:space:]')"
  demangled_count="$(wc -l < "${demangled_file}" | tr -d '[:space:]')"
  if [[ "${symbol_count}" != "${demangled_count}" ]]; then
    fatal "'swift demangle' returned ${demangled_count} names for ${symbol_count} symbols"
  fi

  if ! paste "${symbols_file}" "${demangled_file}"; then
    fatal "Failed to pair the symbols with their demangled names"
  fi
  return 0
}

matches_pattern() {
  local text="${1?matches_pattern requires the text to match, possibly empty}"
  local pattern="${2:?matches_pattern requires the extended regular expression}"

  [[ "${text}" =~ ${pattern} ]]
  return "$?"
}

filter_names() {
  local names_file="${1:?filter_names requires the file of symbols and demangled names}"
  local filter="${2:?filter_names requires the extended regular expression}"

  local symbol demangled_name
  local match_status
  while IFS=$'\t' read -r symbol demangled_name; do
    match_status=0
    matches_pattern "${demangled_name}" "${filter}" || match_status="$?"
    case "${match_status}" in
      0)
        printf -- '%s\t%s\n' "${symbol}" "${demangled_name}"
        ;;
      1)
        ;;
      *)
        fatal "'${filter}' is not a valid extended regular expression"
        ;;
    esac
  done < "${names_file}"
  return 0
}

compare_functions() {
  local names_file="${1:?compare_functions requires the file of symbols and demangled names}"
  local manifest_file="${2:?compare_functions requires the file listing the disassembly listings}"
  local diff_directory="${3?compare_functions requires the diff directory, empty for none}"
  shift 3
  local -a listing_files=( "$@" )

  if ! awk -F '\t' \
    -v names_file="${names_file}" \
    -v manifest_file="${manifest_file}" \
    -v diff_directory="${diff_directory}" '
    function quoted(value) {
      return "\047" value "\047"
    }

    function fatal(message) {
      printf "** ERROR: %s\n", message > "/dev/stderr"
      failed = 1
      exit 1
    }

    function side_name(which) {
      if (which == 1) {
        return "base"
      }
      return "head"
    }

    function is_marker_label(label) {
      return label ~ /^[lL]tmp[0-9]+$/ || label ~ /^\.L/ || label ~ /^\$[adtx](\..*)?$/
    }

    function mnemonic_of(text,    mnemonic) {
      mnemonic = text
      sub(/[[:space:]].*$/, "", mnemonic)
      return mnemonic
    }

    function same_body(first_block, second_block,    position, first_line, second_line) {
      if (block_count[first_block] != block_count[second_block]) {
        return 0
      }
      for (position = 1; position <= block_count[first_block]; position++) {
        first_line = block_line[first_block, position]
        second_line = block_line[second_block, position]
        if (first_line != second_line) {
          return 0
        }
      }
      return 1
    }

    function write_body(block, path,    position) {
      printf "" > path
      for (position = 1; position <= block_count[block]; position++) {
        print block_line[block, position] > path
      }
      close(path)
    }

    function finish_block(    kept_total, position, label_index, label, real_total) {
      if (pending_label_total == 0 && pending_instruction_total == 0) {
        return
      }

      kept_total = pending_instruction_total
      while (kept_total > 0 && mnemonic_of(pending_instruction[kept_total]) ~ /^nop/) {
        kept_total--
      }

      block_total++
      block_count[block_total] = kept_total
      block_qualifier[block_total] = qualifier
      for (position = 1; position <= kept_total; position++) {
        block_line[block_total, position] = pending_instruction[position]
      }

      real_total = 0
      for (label_index = 1; label_index <= pending_label_total; label_index++) {
        label = pending_label[label_index]
        if (is_marker_label(label)) {
          continue
        }
        real_total++
        if (!(label in demangled_of)) {
          continue
        }
        if (!((side, label) in definition_total)) {
          label_total[side]++
          label_order[side, label_total[side]] = label
        }
        definition_total[side, label]++
        definition_block[side, label, definition_total[side, label]] = block_total
      }

      if (real_total == 0 && kept_total > 0) {
        orphan_instruction_total += kept_total
      }

      pending_label_total = 0
      pending_instruction_total = 0
      instruction_seen = 0
    }

    function register_entity(which, key, block, label, entity_qualifier_text,    description) {
      if ((which, key) in entity_block) {
        description = "The symbol " quoted(label) " is defined more than once"
        description = description " in the " side_name(which) " object files named "
        description = description quoted(entity_qualifier_text)
        description = description ", with different instructions"
        fatal(description)
      }
      entity_total[which]++
      entity_order[which, entity_total[which]] = key
      entity_block[which, key] = block
      entity_label[which, key] = label
      entity_qualifier[which, key] = entity_qualifier_text
    }

    function build_entities(which,    label_index, label, definition, first_block, other_block,
                            ambiguous) {
      for (label_index = 1; label_index <= label_total[which]; label_index++) {
        label = label_order[which, label_index]
        first_block = definition_block[which, label, 1]
        ambiguous = 0
        for (definition = 2; definition <= definition_total[which, label]; definition++) {
          if (!same_body(first_block, definition_block[which, label, definition])) {
            ambiguous = 1
            break
          }
        }
        if (!ambiguous) {
          register_entity(which, label, first_block, label, "")
          continue
        }
        for (definition = 1; definition <= definition_total[which, label]; definition++) {
          other_block = definition_block[which, label, definition]
          register_entity(which, label SUBSEP block_qualifier[other_block], other_block, label,
                          block_qualifier[other_block])
        }
      }
    }

    function entity_display_name(which, key,    name) {
      name = demangled_of[entity_label[which, key]]
      if (entity_qualifier[which, key] != "") {
        name = name " [" entity_qualifier[which, key] "]"
      }
      return name
    }

    function entity_display_symbol(which, key,    symbol_text) {
      symbol_text = entity_label[which, key]
      if (entity_qualifier[which, key] != "") {
        symbol_text = symbol_text " [" entity_qualifier[which, key] "]"
      }
      return symbol_text
    }

    FILENAME == names_file {
      demangled_of[$1] = $2
      next
    }

    FILENAME == manifest_file {
      side_of_listing[$1] = $2
      qualifier_of_listing[$1] = $3
      next
    }

    FNR == 1 {
      finish_block()
      if (!(FILENAME in side_of_listing)) {
        fatal("The listing " quoted(FILENAME) " is not in " quoted(manifest_file))
      }
      side = side_of_listing[FILENAME]
      qualifier = qualifier_of_listing[FILENAME]
    }

    /^<.*>:$/ {
      if (instruction_seen) {
        finish_block()
      }
      pending_label_total++
      pending_label[pending_label_total] = substr($0, 2, length($0) - 3)
      next
    }

    /^\t/ {
      instruction_seen = 1
      pending_instruction_total++
      text = $0
      sub(/^\t/, "", text)
      pending_instruction[pending_instruction_total] = text
      next
    }

    {
      fatal("Cannot read the line " quoted($0) " of " quoted(FILENAME))
    }

    END {
      if (failed) {
        exit 1
      }
      finish_block()

      if (label_total[1] + label_total[2] == 0) {
        fatal("Found no functions in the disassembly listings")
      }
      if (orphan_instruction_total > 0) {
        printf "** WARNING: ignored %d instructions that follow no function symbol\n",
          orphan_instruction_total > "/dev/stderr"
      }

      build_entities(1)
      build_entities(2)

      for (position = 1; position <= entity_total[1]; position++) {
        key = entity_order[1, position]
        if (!((2, key) in entity_block)) {
          only_base_total++
          only_base_key[only_base_total] = key
        } else if (same_body(entity_block[1, key], entity_block[2, key])) {
          same_total++
        } else {
          changed_total++
          changed_key[changed_total] = key
        }
      }
      for (position = 1; position <= entity_total[2]; position++) {
        key = entity_order[2, position]
        if (!((1, key) in entity_block)) {
          only_head_total++
          only_head_key[only_head_total] = key
        }
      }

      if (changed_total > 0) {
        printf "section\tchanged\t%d\n", changed_total
      }
      for (position = 1; position <= changed_total; position++) {
        key = changed_key[position]
        base_block = entity_block[1, key]
        head_block = entity_block[2, key]
        base_count = block_count[base_block]
        head_count = block_count[head_block]
        if (head_count < base_count) {
          verdict = "shorter"
          shorter_total++
        } else if (head_count > base_count) {
          verdict = "longer"
          longer_total++
        } else {
          verdict = "different"
          different_total++
        }
        printf "changed\t%s\t%s\t%d\t%d\t%s\t%d\n",
          entity_display_name(1, key), entity_display_symbol(1, key),
          base_count, head_count, verdict, position
        if (diff_directory != "") {
          write_body(base_block, diff_directory "/" position ".base")
          write_body(head_block, diff_directory "/" position ".head")
        }
      }

      if (only_base_total > 0) {
        printf "section\tonly_base\t%d\n", only_base_total
      }
      for (position = 1; position <= only_base_total; position++) {
        key = only_base_key[position]
        printf "only_base\t%s\t%s\t%d\n",
          entity_display_name(1, key), entity_display_symbol(1, key),
          block_count[entity_block[1, key]]
      }

      if (only_head_total > 0) {
        printf "section\tonly_head\t%d\n", only_head_total
      }
      for (position = 1; position <= only_head_total; position++) {
        key = only_head_key[position]
        printf "only_head\t%s\t%s\t%d\n",
          entity_display_name(2, key), entity_display_symbol(2, key),
          block_count[entity_block[2, key]]
      }

      printf "summary\t%d\t%d\t%d\t%d\t%d\t%d\n",
        same_total, shorter_total, longer_total, different_total, only_base_total, only_head_total
    }
  ' "${names_file}" "${manifest_file}" "${listing_files[@]}"; then
    fatal "The comparison of the functions failed"
  fi
  return 0
}

print_unified_diff() {
  local symbol="${1:?print_unified_diff requires the symbol of the function}"
  local base_body_file="${2:?print_unified_diff requires the base function body}"
  local head_body_file="${3:?print_unified_diff requires the head function body}"

  local -a diff_arguments=( -u -L "base: ${symbol}" -L "head: ${symbol}" )
  local diff_status=0
  diff "${diff_arguments[@]}" "${base_body_file}" "${head_body_file}" || diff_status="$?"
  if [[ "${diff_status}" -ne 1 ]]; then
    fatal "'diff' exited ${diff_status} instead of 1 on the function '${symbol}'"
  fi
  return 0
}

print_report() {
  local results_file="${1:?print_report requires the file of results}"
  local diff_directory="${2?print_report requires the diff directory, empty for none}"

  local line record_kind
  local demangled_name symbol base_count head_count verdict diff_index
  local -a fields=()
  local separator=""
  while IFS= read -r line; do
    IFS=$'\t' read -r -a fields <<< "${line}"
    record_kind="${fields[0]}"
    case "${record_kind}" in
      section)
        printf -- '%s' "${separator}"
        separator=$'\n'
        case "${fields[1]}" in
          changed)
            printf -- 'Changed (%d):\n' "${fields[2]}"
            ;;
          only_base)
            printf -- 'Only in base (%d):\n' "${fields[2]}"
            ;;
          only_head)
            printf -- 'Only in head (%d):\n' "${fields[2]}"
            ;;
          *)
            fatal "Found the unknown section '${fields[1]}' in the results of the comparison"
            ;;
        esac
        ;;
      changed)
        demangled_name="${fields[1]}"
        symbol="${fields[2]}"
        base_count="${fields[3]}"
        head_count="${fields[4]}"
        verdict="${fields[5]}"
        diff_index="${fields[6]}"
        printf -- '  base=%-5d head=%-5d %-9s %s\n' \
          "${base_count}" "${head_count}" "${verdict}" "${demangled_name}"
        if [[ -n "${diff_directory}" ]]; then
          print_unified_diff "${symbol}" \
            "${diff_directory}/${diff_index}.base" "${diff_directory}/${diff_index}.head"
        fi
        ;;
      only_base | only_head)
        printf -- '  %-5d %s\n' "${fields[3]}" "${fields[1]}"
        ;;
      summary)
        printf -- '%sSummary of %d functions\n' "${separator}" \
          "$(( fields[1] + fields[2] + fields[3] + fields[4] + fields[5] + fields[6] ))"
        printf -- '  %-12s %d\n' "same" "${fields[1]}"
        printf -- '  %-12s %d\n' "shorter" "${fields[2]}"
        printf -- '  %-12s %d\n' "longer" "${fields[3]}"
        printf -- '  %-12s %d\n' "different" "${fields[4]}"
        printf -- '  %-12s %d\n' "only in base" "${fields[5]}"
        printf -- '  %-12s %d\n' "only in head" "${fields[6]}"
        ;;
      *)
        fatal "Found the unknown record '${record_kind}' in the results of the comparison"
        ;;
    esac
  done < "${results_file}"
  return 0
}

count_differences() {
  local results_file="${1:?count_differences requires the file of results}"

  local line
  local -a fields=()
  while IFS= read -r line; do
    IFS=$'\t' read -r -a fields <<< "${line}"
    if [[ "${fields[0]}" == "summary" ]]; then
      printf -- '%d\n' "$(( fields[2] + fields[3] + fields[4] + fields[5] + fields[6] ))"
      return 0
    fi
  done < "${results_file}"

  fatal "Found no summary in the results of the comparison"
}

main() {
  require_command swift
  require_command diff

  parse_arguments "$@"

  if [[ ! -x "${normalize_script}" ]]; then
    fatal "There is no executable '${normalize_script}' to normalize the object files with"
  fi

  workspace="$(mktemp -d)" || fatal "Failed to create a temporary directory for the comparison"
  trap cleanup EXIT
  local -r manifest_file="${workspace}/listings.tsv"
  local -r symbols_file="${workspace}/symbols.txt"
  local -r demangled_file="${workspace}/demangled.txt"
  local -r names_file="${workspace}/names.tsv"
  local -r filtered_names_file="${workspace}/filtered-names.tsv"
  local -r results_file="${workspace}/results.tsv"
  local -r diff_directory="${workspace}/diffs"

  local -a listing_files=()
  local -r base_listing_directory="${workspace}/base"
  local -r head_listing_directory="${workspace}/head"
  normalize_object_files base 1 base_object_files listing_files \
    "${base_listing_directory}" "${manifest_file}"
  normalize_object_files head 2 head_object_files listing_files \
    "${head_listing_directory}" "${manifest_file}"

  log "Demangling the symbols..."
  if ! demangle_symbols "${symbols_file}" "${demangled_file}" "${listing_files[@]}" \
    > "${names_file}"; then
    fatal "Failed to write the demangled names to '${names_file}'"
  fi

  local compared_names_file="${names_file}"
  if [[ -n "${name_filter}" ]]; then
    if ! filter_names "${names_file}" "${name_filter}" > "${filtered_names_file}"; then
      fatal "Failed to write the filtered names to '${filtered_names_file}'"
    fi
    if [[ ! -s "${filtered_names_file}" ]]; then
      fatal "The filter '${name_filter}' matches no function in the base or the head object files"
    fi
    compared_names_file="${filtered_names_file}"
  fi

  local diff_directory_argument=""
  if [[ "${verbose}" == "true" ]]; then
    if ! mkdir -p -- "${diff_directory}"; then
      fatal "Failed to create the directory '${diff_directory}'"
    fi
    diff_directory_argument="${diff_directory}"
  fi

  log "Comparing the functions..."
  if ! compare_functions "${compared_names_file}" "${manifest_file}" "${diff_directory_argument}" \
    "${listing_files[@]}" > "${results_file}"; then
    fatal "Failed to write the results of the comparison to '${results_file}'"
  fi
  print_report "${results_file}" "${diff_directory_argument}"

  local difference_total
  difference_total="$(count_differences "${results_file}")"
  if [[ "${difference_total}" -gt 0 ]]; then
    exit 1
  fi
  return 0
}

main "$@"
