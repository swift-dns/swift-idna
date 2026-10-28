#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s failglob
IFS=$'\n\t'

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 1; }

check_only="false"
declare -a object_files=()
workspace=""

cleanup() {
  if [[ -n "${workspace}" && -d "${workspace}" ]]; then
    rm -rf -- "${workspace}"
  fi
  return 0
}

usage() {
  printf -- 'Usage: %s [--check] <object file>...\n' "$(basename -- "${BASH_SOURCE[0]}")"
  printf -- '  --check only verify that an objdump is available, taking no object files\n'
  return 0
}

parse_arguments() {
  local option
  while [[ "$#" -gt 0 ]]; do
    option="$1"
    shift
    case "${option}" in
      --check)
        check_only="true"
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      --)
        object_files+=( "$@" )
        break
        ;;
      -*)
        fatal "Unknown argument '${option}'" "$(usage)"
        ;;
      *)
        object_files+=( "${option}" )
        ;;
    esac
  done

  if [[ "${check_only}" == "true" && "${#object_files[@]}" -gt 0 ]]; then
    fatal "--check takes no object files" "$(usage)"
  fi
  if [[ "${check_only}" != "true" && "${#object_files[@]}" -eq 0 ]]; then
    fatal "Found no object files to normalize" "$(usage)"
  fi
  return 0
}

validate_object_files() {
  local -n object_files_ref="${1:?validate_object_files requires the name of the object file array}"

  local object_file
  for object_file in "${object_files_ref[@]}"; do
    if [[ ! -f "${object_file}" ]]; then
      fatal "There is no object file '${object_file}' to normalize"
    fi
  done
  return 0
}

find_objdump() {
  local objdump_path

  case "$(uname -s)" in
    Darwin)
      if ! objdump_path="$(xcrun --find objdump)"; then
        fatal "'xcrun --find objdump' did not find an objdump"
      fi
      ;;
    *)
      if ! objdump_path="$(command -v llvm-objdump)"; then
        fatal "'llvm-objdump' is required on $(uname -s) but is not on the PATH" \
          "GNU objdump lacks '--no-leading-addr' and '--show-all-symbols', so it cannot stand in"
      fi
      ;;
  esac

  printf -- '%s\n' "${objdump_path}"
  return 0
}

run_objdump() {
  local objdump_path="${1:?run_objdump requires the path of objdump}"
  local object_file="${2:?run_objdump requires the object file}"
  local output_file="${3:?run_objdump requires the file to write the output to}"
  local dumped_content="${4:?run_objdump requires a description of what it dumps}"
  shift 4

  if ! "${objdump_path}" "$@" "${object_file}" > "${output_file}"; then
    fatal "Failed to dump the ${dumped_content} of '${object_file}'"
  fi
  return 0
}

normalize_disassembly() {
  local objdump_path="${1:?normalize_disassembly requires the path of objdump}"
  local object_file="${2:?normalize_disassembly requires the object file}"
  local dump_directory="${3:?normalize_disassembly requires the directory to write the dumps to}"

  local -r sections_file="${dump_directory}/object-sections.txt"
  local -r symbols_file="${dump_directory}/object-symbols.txt"
  local -r contents_file="${dump_directory}/object-contents.txt"
  local -r disassembly_file="${dump_directory}/object-disassembly.txt"

  local -a disassemble_arguments=(
    --disassemble
    --no-show-raw-insn
    --no-leading-addr
    --show-all-symbols
    --reloc
  )
  run_objdump "${objdump_path}" "${object_file}" "${sections_file}" "section headers" \
    --section-headers
  run_objdump "${objdump_path}" "${object_file}" "${symbols_file}" "symbol table" --syms
  run_objdump "${objdump_path}" "${object_file}" "${contents_file}" "section contents" \
    --full-contents
  run_objdump "${objdump_path}" "${object_file}" "${disassembly_file}" "disassembly" \
    "${disassemble_arguments[@]}"

  if ! awk \
    -v object_file="${object_file}" \
    -v sections_file="${sections_file}" \
    -v symbols_file="${symbols_file}" \
    -v contents_file="${contents_file}" '
    BEGIN {
      dump_groups = 4
      dump_group_digits = 8
      hex_area_width = dump_groups * dump_group_digits + dump_groups - 1
    }

    function quoted(value) {
      return "\047" value "\047"
    }

    function fatal(message) {
      printf "** ERROR: %s\n", message > "/dev/stderr"
      failed = 1
      exit 1
    }

    function unresolvable(reason,    description) {
      description = "Cannot resolve the relocation " quoted(resolving_relocation)
      description = description "\n  object:      " object_file
      description = description "\n  function:    " block_label_list
      description = description "\n  instruction: " collapsed(pending_instruction)
      description = description "\n  reason:      " reason
      fatal(description)
    }

    function hex_value(digits,    value, position) {
      if (digits !~ /^[0-9a-fA-F]+$/) {
        fatal(quoted(digits) " is not a hexadecimal number, as found in " object_file)
      }
      digits = tolower(digits)
      value = 0
      for (position = 1; position <= length(digits); position++) {
        value = value * 16 + index("0123456789abcdef", substr(digits, position, 1)) - 1
      }
      return value
    }

    function constant_size(section) {
      if (section ~ /literal16|cst16/) {
        return 16
      }
      if (section ~ /literal8|cst8/) {
        return 8
      }
      if (section ~ /literal4|cst4/) {
        return 4
      }
      return 0
    }

    function without_segment(section) {
      sub(/^[^,]*,/, "", section)
      return section
    }

    function set_object_format(format) {
      is_macho = (format ~ /^mach-o /)
      if (format == "mach-o 64-bit x86-64" || format == "elf64-x86-64") {
        architecture = "x86"
      } else if (format == "mach-o arm64" || format == "elf64-littleaarch64") {
        architecture = "arm64"
      } else {
        fatal(object_file " has the unsupported object format " quoted(format))
      }
    }

    function comment_position(text) {
      if (architecture == "x86") {
        return index(text, "#")
      }
      if (match(text, /;|\/\//)) {
        return RSTART
      }
      return 0
    }

    function is_comment_line(line) {
      if (architecture == "x86") {
        return line ~ /^[[:space:]]+#/
      }
      return line ~ /^[[:space:]]+(;|\/\/)/
    }

    function commented_address_digits(comment) {
      if (match(comment, /^#+[[:space:]]+0x[0-9a-fA-F]+/)) {
        comment = substr(comment, RSTART, RLENGTH)
        sub(/^#+[[:space:]]+0x/, "", comment)
        return comment
      }
      return ""
    }

    function collapsed(text) {
      gsub(/[[:space:]]+/, " ", text)
      sub(/^ /, "", text)
      sub(/ $/, "", text)
      return text
    }

    function normalized_target(target,    symbol, offset) {
      sub(/^0x[0-9a-fA-F]+ </, "", target)
      sub(/>$/, "", target)
      symbol = target
      offset = ""
      if (match(target, /\+0x[0-9a-fA-F]+$/)) {
        symbol = substr(target, 1, RSTART - 1)
        offset = substr(target, RSTART)
      }
      if (symbol in block_labels) {
        if (offset == "") {
          offset = "+0x0"
        }
        return "<" offset ">"
      }
      return "<" target ">"
    }

    function rewritten_targets(text,    result, target_start, target_length) {
      result = ""
      while (match(text, /0x[0-9a-fA-F]+ <[^>]*>/)) {
        target_start = RSTART
        target_length = RLENGTH
        result = result substr(text, 1, target_start - 1)
        result = result normalized_target(substr(text, target_start, target_length))
        text = substr(text, target_start + target_length)
      }
      return result text
    }

    function symbol_text(symbol) {
      if (is_macho) {
        sub(/^_/, "", symbol)
      }
      return symbol
    }

    function offset_text(addend, addend_sign) {
      if (addend == 0 || (architecture == "x86" && addend_sign == "-")) {
        return ""
      }
      return addend_sign sprintf("0x%x", addend)
    }

    function is_local_label(symbol) {
      if (is_macho) {
        return symbol !~ /^_/
      }
      return symbol ~ /^\.L/ || symbol ~ /^__unnamed_[0-9]+$/
    }

    function symbol_name_annotation(kind, symbol, addend, addend_sign) {
      return "{" kind ":" symbol_text(symbol) offset_text(addend, addend_sign) "}"
    }

    function got_annotation(symbol) {
      if (symbol_ambiguous[symbol]) {
        unresolvable("the symbol " quoted(symbol) " is defined more than once")
      }
      return "{got:" symbol_text(symbol) "}"
    }

    function constant_annotation(section, address, size,    offset, bytes, missing) {
      if (!is_macho && section_count[section] > 1) {
        unresolvable("several sections are named " quoted(section))
      }
      bytes = ""
      for (offset = 0; offset < size; offset++) {
        if (!((section, address + offset) in constant_byte)) {
          missing = sprintf("0x%x", address + offset)
          unresolvable("the section " quoted(section) " holds no byte at " missing)
        }
        bytes = bytes constant_byte[section, address + offset]
      }
      return "{const:" bytes "}"
    }

    function target_address_in_section(section, comment_digits,    address, position) {
      if (comment_digits == "") {
        unresolvable("the comment of the instruction holds no target address")
      }
      address = hex_value(comment_digits)
      for (position = 1; position <= section_total; position++) {
        if (section_name[position] == section &&
            section_vma[position] <= address &&
            address < section_vma[position] + section_size[position]) {
          return address
        }
      }
      unresolvable("the address 0x" comment_digits " is outside of the section " quoted(section))
    }

    function code_target_annotation(section, addend, addend_sign, relocation_type,
                                    address, found, description) {
      address = addend
      if (addend_sign == "-") {
        address = -addend
      }
      if (architecture == "x86") {
        if (relocation_type !~ /_(PC32|PLT32)$/) {
          unresolvable("the PC bias of its type is unknown, so the target in " quoted(section) " is too")
        }
        address = address + 4
      }
      if (address < 0) {
        unresolvable("it targets before the start of the code section " quoted(section))
      }
      found = function_total[section, address] + 0
      if (found != 1) {
        description = found " function symbols of the section " quoted(section)
        unresolvable(description " start at " sprintf("0x%x", address))
      }
      return symbol_annotation(function_name[section, address], 0, "+")
    }

    function section_annotation(section, addend, addend_sign, comment_digits, relocation_type,
                                size, address) {
      if (section_is_code[section_position[section]]) {
        return code_target_annotation(section, addend, addend_sign, relocation_type)
      }
      size = constant_size(section)
      if (size == 0) {
        return "{data:" section "}"
      }
      if (is_macho && architecture == "x86") {
        address = target_address_in_section(section, comment_digits)
      } else if (!is_macho && architecture == "arm64" && addend_sign == "+") {
        address = addend
      } else {
        unresolvable("the offset within the section " quoted(section) " is unknown for this format")
      }
      return constant_annotation(section, address, size)
    }

    function symbol_annotation(symbol, addend, addend_sign,    section, size) {
      if (symbol_ambiguous[symbol]) {
        unresolvable("the symbol " quoted(symbol) " is defined more than once")
      }
      section = symbol_section[symbol]
      if (section == "*UND*") {
        return symbol_name_annotation("sym", symbol, addend, addend_sign)
      }
      if (!(section in section_position)) {
        unresolvable("the section " quoted(section) " of the symbol " quoted(symbol) " is unknown")
      }
      if (section_is_code[section_position[section]]) {
        return symbol_name_annotation("sym", symbol, addend, addend_sign)
      }
      size = constant_size(section)
      if (size == 0) {
        if (is_local_label(symbol)) {
          return "{data:" section "}"
        }
        return symbol_name_annotation("data", symbol, addend, addend_sign)
      }
      if (architecture == "arm64" && addend != 0) {
        unresolvable("its addend offsets the symbol on arm64, which is not resolved")
      }
      return constant_annotation(section, symbol_value[symbol], size)
    }

    function relocation_annotation(relocation_type, relocation_target, comment_digits,
                                   base, addend, addend_sign, through_got) {
      resolving_relocation = relocation_type " " relocation_target
      base = relocation_target
      through_got = sub(/@GOTPCREL$/, "", base)
      addend = 0
      addend_sign = "+"
      if (match(base, /[+-]0x[0-9a-fA-F]+$/)) {
        addend_sign = substr(base, RSTART, 1)
        addend = hex_value(substr(base, RSTART + 3))
        base = substr(base, 1, RSTART - 1)
      } else if (match(base, /[+-][0-9]+$/)) {
        addend_sign = substr(base, RSTART, 1)
        addend = substr(base, RSTART + 1) + 0
        base = substr(base, 1, RSTART - 1)
      }

      if (through_got && base in symbol_section) {
        return got_annotation(base)
      }
      if (!through_got && base in section_position) {
        return section_annotation(base, addend, addend_sign, comment_digits, relocation_type)
      }
      if (!through_got && base in symbol_section) {
        return symbol_annotation(base, addend, addend_sign)
      }
      unresolvable("its target is neither a section nor a symbol of the object")
    }

    function flush_instruction(    text, relocation_index, annotation) {
      if (!instruction_pending) {
        return
      }
      instruction_pending = 0
      if (pending_addend != "") {
        unresolvable("no relocation follows it for the addend to apply to")
      }

      text = pending_instruction
      if (relocation_total == 0) {
        text = collapsed(rewritten_targets(text))
      } else {
        if (architecture == "x86") {
          gsub(/-?0x[0-9a-fA-F]+\(%rip\)/, "(%rip)", text)
        }
        gsub(/0x[0-9a-fA-F]+ <[^>]*>/, "", text)
        text = collapsed(text)
        for (relocation_index = 1; relocation_index <= relocation_total; relocation_index++) {
          annotation = relocation_annotation(relocation_type[relocation_index],
                                             relocation_target[relocation_index],
                                             pending_comment_digits)
          text = text " " annotation
        }
      }
      print "\t" text
    }

    FILENAME == sections_file {
      if ($1 ~ /^[0-9]+$/ && NF >= 4 && $3 ~ /^[0-9a-fA-F]+$/ && $4 ~ /^[0-9a-fA-F]+$/) {
        section_total++
        section_name[section_total] = $2
        section_size[section_total] = hex_value($3)
        section_vma[section_total] = hex_value($4)
        section_is_code[section_total] = 0
        for (field = 5; field <= NF; field++) {
          if ($field == "TEXT") {
            section_is_code[section_total] = 1
          }
        }
        if (!($2 in section_position)) {
          section_position[$2] = section_total
        }
        section_count[$2]++
      }
      next
    }

    FILENAME == symbols_file {
      if ($1 ~ /^[0-9a-fA-F]+$/ && NF >= 3) {
        field = 2
        while (field < NF && $field ~ /^[lgu!wCWiIdDfFO]+$/) {
          field++
        }
        symbol_name = $NF
        name_skip = field
        if (index($field, ",") == 0) {
          name_skip = field + 1
        }
        if (NF > name_skip + 1 || $0 ~ /[[:space:]]$/) {
          symbol_name = $0
          for (name_field = 1; name_field <= name_skip; name_field++) {
            sub(/^[[:space:]]*[^[:space:]]+[[:space:]]?/, "", symbol_name)
          }
          sub(/^\.(hidden|protected|internal) /, "", symbol_name)
        }
        if (symbol_name in symbol_section) {
          symbol_ambiguous[symbol_name] = 1
        }
        symbol_section[symbol_name] = without_segment($field)
        symbol_value[symbol_name] = hex_value($1)
        symbol_flags = ""
        for (flag_field = 2; flag_field < field; flag_field++) {
          symbol_flags = symbol_flags $flag_field
        }
        if (symbol_flags ~ /F/) {
          function_total[symbol_section[symbol_name], symbol_value[symbol_name]]++
          function_name[symbol_section[symbol_name], symbol_value[symbol_name]] = symbol_name
        }
      }
      next
    }

    FILENAME == contents_file {
      if ($0 ~ /^Contents of section /) {
        block_section = $0
        sub(/^Contents of section /, "", block_section)
        sub(/:$/, "", block_section)
        block_section = without_segment(block_section)
        block_is_constant = (constant_size(block_section) > 0)
      } else if (block_is_constant && $0 ~ /^ [0-9a-fA-F]+ /) {
        line_address = $0
        sub(/^ /, "", line_address)
        sub(/ .*$/, "", line_address)
        hex_area = substr($0, length(line_address) + 3, hex_area_width)
        gsub(/ /, "", hex_area)
        if (hex_area !~ /^([0-9a-fA-F][0-9a-fA-F])*$/) {
          fatal("Cannot read the bytes of " quoted($0) " in " object_file)
        }
        line_address = hex_value(line_address)
        for (byte_position = 1; byte_position * 2 <= length(hex_area); byte_position++) {
          byte_digits = substr(hex_area, byte_position * 2 - 1, 2)
          constant_byte[block_section, line_address + byte_position - 1] = tolower(byte_digits)
        }
      }
      next
    }

    /:\tfile format / {
      object_format = $0
      sub(/^.*:\tfile format /, "", object_format)
      set_object_format(object_format)
      next
    }

    /^<.*>:$/ {
      flush_instruction()
      if (instruction_seen) {
        delete block_labels
        block_label_list = ""
        instruction_seen = 0
      }
      label = substr($0, 2, length($0) - 3)
      block_labels[label] = 1
      if (block_label_list == "") {
        block_label_list = label
      } else {
        block_label_list = block_label_list ", " label
      }
      print $0
      next
    }

    /^\t\t/ {
      if (!instruction_pending) {
        fatal("Found a relocation outside of an instruction in " object_file ": " quoted($0))
      }
      if (split($0, relocation_fields, "\t") != 4) {
        fatal("Cannot read the relocation " quoted($0) " in " object_file)
      }
      if (relocation_fields[3] == "ARM64_RELOC_ADDEND") {
        resolving_relocation = relocation_fields[3] " " relocation_fields[4]
        if (relocation_fields[4] !~ /^0x[0-9a-fA-F]+$/) {
          fatal("Cannot read the addend of " quoted($0) " in " object_file)
        }
        if (pending_addend != "") {
          unresolvable("another addend relocation precedes it")
        }
        addend_value = hex_value(substr(relocation_fields[4], 3))
        if (addend_value >= 8388608) {
          unresolvable("its addend does not fit in 23 bits, so it may be negative")
        }
        pending_addend = sprintf("+0x%x", addend_value)
        next
      }
      relocation_total++
      relocation_type[relocation_total] = relocation_fields[3]
      relocation_target[relocation_total] = relocation_fields[4] pending_addend
      pending_addend = ""
      next
    }

    is_comment_line($0) {
      if (!instruction_pending) {
        fatal("Found a comment outside of an instruction in " object_file ": " quoted($0))
      }
      if (pending_comment_digits == "") {
        comment_text = $0
        sub(/^[[:space:]]+/, "", comment_text)
        pending_comment_digits = commented_address_digits(comment_text)
      }
      next
    }

    /^[[:space:]]+[^[:space:]]/ {
      flush_instruction()
      if (architecture == "") {
        fatal("Found an instruction before the object format of " object_file)
      }
      instruction_seen = 1
      instruction_pending = 1
      relocation_total = 0
      pending_instruction = $0
      sub(/^[[:space:]]+/, "", pending_instruction)
      pending_comment_digits = ""
      comment_start = comment_position(pending_instruction)
      if (comment_start > 0) {
        comment_text = substr(pending_instruction, comment_start)
        pending_comment_digits = commented_address_digits(comment_text)
        pending_instruction = substr(pending_instruction, 1, comment_start - 1)
      }
      next
    }

    {
      flush_instruction()
    }

    END {
      if (failed) {
        exit 1
      }
      flush_instruction()
    }
  ' "${sections_file}" "${symbols_file}" "${contents_file}" "${disassembly_file}"; then
    fatal "Failed to normalize the disassembly of '${object_file}'"
  fi
  return 0
}

disassemble() {
  local objdump_path="${1:?disassemble requires the path of objdump}"
  local -n object_files_ref="${2:?disassemble requires the name of the object file array}"
  local dump_directory="${3:?disassemble requires the directory to write the dumps to}"

  local object_file
  for object_file in "${object_files_ref[@]}"; do
    normalize_disassembly "${objdump_path}" "${object_file}" "${dump_directory}"
  done
  return 0
}

main() {
  parse_arguments "$@"

  local objdump_path
  objdump_path="$(find_objdump)"
  if [[ "${check_only}" == "true" ]]; then
    return 0
  fi

  validate_object_files object_files

  workspace="$(mktemp -d)" || fatal "Failed to create a temporary directory for the dumps"
  trap cleanup EXIT

  disassemble "${objdump_path}" object_files "${workspace}"
  return 0
}

main "$@"
