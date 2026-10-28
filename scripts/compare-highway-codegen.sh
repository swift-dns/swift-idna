#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s failglob
IFS=$'\n\t'

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 2; }

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repository_root
readonly compare_script="${repository_root}/scripts/compare-disassembly.sh"
readonly normalize_script="${repository_root}/scripts/normalize-disassembly.sh"
readonly highway_url="https://github.com/swift-dns/swift-highway.git"
readonly highway_identity="swift-highway"
readonly resolved_file_name="Package.resolved"
readonly target_name="SwiftIDNA"
readonly path_reference_prefix="path:"
readonly -a macos_sse2_build_arguments=(
  --triple x86_64-apple-macosx
  -Xswiftc -target-cpu -Xswiftc x86-64
  -Xswiftc -Xcc -Xswiftc -march=x86-64
  -Xcc -march=x86-64
  -Xcxx -march=x86-64
)

verbose="false"
old_reference=""
new_reference=""
workspace=""
declare -a target_labels=()
declare -A description_of_side=()
declare -A package_directory_of_side=()
declare -A scratch_directory_of_side=()

cleanup() {
  if [[ -n "${workspace}" && -d "${workspace}" ]]; then
    rm -rf -- "${workspace}"
  fi
  return 0
}

usage() {
  printf -- 'Usage: %s [--verbose] <old swift-highway> <new swift-highway>\n' \
    "$(basename -- "${BASH_SOURCE[0]}")"
  printf -- '  A swift-highway is a tag, a branch or a full commit SHA of\n'
  printf -- '  %s\n' "${highway_url}"
  printf -- '  or "%s<directory>" for a local checkout.\n' "${path_reference_prefix}"
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
  local -a references=()
  while [[ "$#" -gt 0 ]]; do
    option="$1"
    shift
    case "${option}" in
      --verbose)
        verbose="true"
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      --)
        references+=( "$@" )
        break
        ;;
      -*)
        fatal "Unknown argument '${option}'" "$(usage)"
        ;;
      *)
        references+=( "${option}" )
        ;;
    esac
  done

  if [[ "${#references[@]}" -ne 2 ]]; then
    fatal "Expected 2 swift-highway references but found ${#references[@]}" "$(usage)"
  fi
  old_reference="${references[0]}"
  new_reference="${references[1]}"
  if [[ -z "${old_reference}" || -z "${new_reference}" ]]; then
    fatal "A swift-highway reference is empty" "$(usage)"
  fi
  return 0
}

detect_targets() {
  local operating_system machine
  operating_system="$(uname -s)"
  machine="$(uname -m)"

  case "${operating_system}-${machine}" in
    Darwin-arm64)
      target_labels=( NEON SSE2 )
      ;;
    Linux-x86_64)
      target_labels=( SSE2 )
      ;;
    Linux-aarch64 | Linux-arm64)
      target_labels=( NEON )
      ;;
    *)
      fatal "Unsupported host '${operating_system}' on '${machine}'" \
        "Supported hosts are arm64 macOS and x86_64 or aarch64 Linux"
      ;;
  esac
  return 0
}

print_target_build_arguments() {
  local target_label="${1:?print_target_build_arguments requires the label of the target}"

  if [[ "${target_label}" == "SSE2" && "$(uname -s)" == "Darwin" ]]; then
    printf -- '%s\0' "${macos_sse2_build_arguments[@]}"
  fi
  return 0
}

canonical_directory() {
  local directory="${1:?canonical_directory requires the directory}"

  local canonical
  if ! canonical="$(cd -- "${directory}" && pwd -P)"; then
    fatal "Failed to resolve the directory '${directory}'"
  fi

  printf -- '%s\n' "${canonical}"
  return 0
}

assert_embeddable_path() {
  local path="${1:?assert_embeddable_path requires the path}"
  local description="${2:?assert_embeddable_path requires a description of the path}"

  case "${path}" in
    *'"'* | *"\\"* | *$'\n'*)
      fatal "The ${description} contains a quote, a backslash or a newline," \
        "which a Package.swift string cannot hold: '${path}'"
      ;;
  esac
  return 0
}

resolve_git_revision() {
  local reference="${1:?resolve_git_revision requires the tag, branch or commit}"

  if [[ "${reference}" =~ ^[0-9a-f]{40}$ ]]; then
    printf -- '%s\n' "${reference}"
    return 0
  fi

  local listing
  if ! listing="$(
    git ls-remote "${highway_url}" \
      "refs/tags/${reference}" "refs/tags/${reference}^{}" "refs/heads/${reference}"
  )"; then
    fatal "Failed to list the refs of '${highway_url}'"
  fi

  local tag_object="" tag_commit="" branch_commit=""
  local listed_revision listed_ref
  while IFS=$'\t' read -r listed_revision listed_ref; do
    case "${listed_ref}" in
      "refs/tags/${reference}")
        tag_object="${listed_revision}"
        ;;
      "refs/tags/${reference}^{}")
        tag_commit="${listed_revision}"
        ;;
      "refs/heads/${reference}")
        branch_commit="${listed_revision}"
        ;;
    esac
  done <<< "${listing}"

  if [[ -z "${tag_commit}" ]]; then
    tag_commit="${tag_object}"
  fi
  if [[ -z "${tag_commit}" && -z "${branch_commit}" ]]; then
    fatal "'${highway_url}' has no tag or branch named '${reference}'" \
      "Pass a tag, a branch, a full 40-character commit SHA" \
      "or '${path_reference_prefix}<directory>'"
  fi
  if [[ -n "${tag_commit}" && -n "${branch_commit}" ]]; then
    if [[ "${tag_commit}" != "${branch_commit}" ]]; then
      fatal "'${reference}' is both a tag (${tag_commit}) and a branch (${branch_commit}) of" \
        "'${highway_url}'; pass the full commit SHA instead"
    fi
  fi

  if [[ -n "${tag_commit}" ]]; then
    printf -- '%s\n' "${tag_commit}"
  else
    printf -- '%s\n' "${branch_commit}"
  fi
  return 0
}

copy_directory() {
  local source_directory="${1:?copy_directory requires the source directory}"
  local destination_directory="${2:?copy_directory requires the destination directory}"

  if ! mkdir -p -- "${destination_directory}"; then
    fatal "Failed to create the directory '${destination_directory}'"
  fi
  if ! rsync --archive --exclude='.git' --exclude='.build' \
    "${source_directory}/" "${destination_directory}/"; then
    fatal "Failed to copy '${source_directory}' to '${destination_directory}'"
  fi
  return 0
}

list_manifest_files() {
  local package_directory="${1:?list_manifest_files requires the package directory}"

  find "${package_directory}" -maxdepth 1 -type f \
    \( -name 'Package.swift' -o -name 'Package@swift-*.swift' \) -print0 | sort -z
  return 0
}

rewrite_highway_dependency() {
  local manifest_file="${1:?rewrite_highway_dependency requires the manifest file}"
  local declaration="${2:?rewrite_highway_dependency requires the new dependency declaration}"

  local -r rewritten_file="${manifest_file}.rewritten"
  if ! awk \
    -v manifest_file="${manifest_file}" \
    -v declaration="${declaration}" '
    function fatal(message) {
      printf "** ERROR: %s\n", message > "/dev/stderr"
      failed = 1
      exit 1
    }

    function call_end(text, open_position,    depth, position, character, newline_offset) {
      depth = 0
      for (position = open_position; position <= length(text); position++) {
        character = substr(text, position, 1)
        if (character == "\"") {
          position++
          while (position <= length(text) && substr(text, position, 1) != "\"") {
            if (substr(text, position, 1) == "\\") {
              position++
            }
            position++
          }
        } else if (character == "/" && substr(text, position + 1, 1) == "/") {
          newline_offset = index(substr(text, position), "\n")
          if (newline_offset == 0) {
            return 0
          }
          position = position + newline_offset - 1
        } else if (character == "(") {
          depth++
        } else if (character == ")") {
          depth--
          if (depth == 0) {
            return position
          }
        }
      }
      return 0
    }

    {
      source = source $0 "\n"
    }

    END {
      if (failed) {
        exit 1
      }
      cursor = 1
      result = ""
      replaced = 0
      while (1) {
        offset = index(substr(source, cursor), ".package(")
        if (offset == 0) {
          break
        }
        start = cursor + offset - 1
        close_position = call_end(source, start + length(".package"))
        if (close_position == 0) {
          fatal("Cannot find the end of the .package( call at offset " start " of " manifest_file)
        }
        call_text = substr(source, start, close_position - start + 1)
        if (call_text ~ /swift-dns\/swift-highway/) {
          result = result substr(source, cursor, start - cursor) declaration
          replaced++
        } else {
          result = result substr(source, cursor, close_position - cursor + 1)
        }
        cursor = close_position + 1
      }
      result = result substr(source, cursor)
      if (replaced != 1) {
        fatal("Expected 1 swift-highway dependency in " manifest_file " but found " replaced)
      }
      printf "%s", result
    }
  ' "${manifest_file}" > "${rewritten_file}"; then
    fatal "Failed to rewrite the swift-highway dependency of '${manifest_file}'"
  fi
  if ! mv -f -- "${rewritten_file}" "${manifest_file}"; then
    fatal "Failed to replace '${manifest_file}' with its rewritten copy"
  fi
  return 0
}

write_pinned_resolved_file() {
  local source_resolved_file="${1:?write_pinned_resolved_file requires the Package.resolved}"
  local destination_resolved_file="${2:?write_pinned_resolved_file requires the file to write}"

  if ! jq --arg identity "${highway_identity}" '
    if .version == 2 or .version == 3 then
      .pins |= map(select(.identity != $identity)) | del(.originHash)
    else
      error("version \(.version) of Package.resolved is not supported")
    end
  ' "${source_resolved_file}" > "${destination_resolved_file}"; then
    fatal "Failed to copy the pins other than ${highway_identity} out of '${source_resolved_file}'"
  fi
  return 0
}

list_held_pins() {
  local resolved_file="${1:?list_held_pins requires the Package.resolved}"

  if ! jq --raw-output --arg identity "${highway_identity}" '
    .pins[] | select(.identity != $identity)
    | [.identity, (.state.revision // ""), (.state.version // ""), (.state.branch // "")]
    | @tsv
  ' "${resolved_file}" | LC_ALL=C sort; then
    fatal "Failed to list the pins of '${resolved_file}'"
  fi
  return 0
}

verify_held_pins() {
  local side="${1:?verify_held_pins requires the name of the side}"
  local resolved_file="${2:?verify_held_pins requires the Package.resolved the side resolved to}"

  local expected_pins resolved_pins
  expected_pins="$(list_held_pins "${repository_root}/${resolved_file_name}")"
  resolved_pins="$(list_held_pins "${resolved_file}")"

  local moved_pins added_pins
  if ! moved_pins="$(
    LC_ALL=C comm -23 <(printf -- '%s\n' "${expected_pins}") <(printf -- '%s\n' "${resolved_pins}")
  )"; then
    fatal "Failed to compare the pins of the ${side} swift-highway with the expected ones"
  fi
  if ! added_pins="$(
    LC_ALL=C comm -13 <(printf -- '%s\n' "${expected_pins}") <(printf -- '%s\n' "${resolved_pins}")
  )"; then
    fatal "Failed to compare the pins of the ${side} swift-highway with the expected ones"
  fi
  if [[ -n "${moved_pins}" ]]; then
    fatal "Resolving the ${side} swift-highway moved dependencies other than ${highway_identity}," \
      "which would confound the comparison. Expected pins missing after the resolution" \
      "(identity, revision, version, branch):" "${moved_pins}"
  fi
  if [[ -n "${added_pins}" ]]; then
    log "The ${side} swift-highway added dependencies, which are not held identical:"
    log "${added_pins}"
  fi

  local held_total
  held_total="$(printf -- '%s\n' "${expected_pins}" | grep -c . || true)"
  log "Held ${held_total} other pinned dependencies identical for the ${side} swift-highway."
  return 0
}

verify_git_highway() {
  local side="${1:?verify_git_highway requires the name of the side}"
  local resolved_file="${2:?verify_git_highway requires the resolved Package.resolved}"
  local expected_revision="${3:?verify_git_highway requires the expected revision}"

  local resolved_revision
  if ! resolved_revision="$(
    jq --raw-output --arg identity "${highway_identity}" \
      '[.pins[] | select(.identity == $identity) | .state.revision] | first // ""' \
      "${resolved_file}"
  )"; then
    fatal "Failed to read the ${highway_identity} pin of '${resolved_file}'"
  fi
  if [[ "${resolved_revision}" != "${expected_revision}" ]]; then
    fatal "The ${side} swift-highway resolved to '${resolved_revision}'" \
      "instead of '${expected_revision}'"
  fi
  return 0
}

verify_path_highway() {
  local side="${1:?verify_path_highway requires the name of the side}"
  local package_directory="${2:?verify_path_highway requires the package directory}"
  local scratch_directory="${3:?verify_path_highway requires the scratch directory}"
  local expected_directory="${4:?verify_path_highway requires the expected dependency directory}"

  local dependency_path
  if ! dependency_path="$(
    swift package --package-path "${package_directory}" --scratch-path "${scratch_directory}" \
      show-dependencies --format json \
      | jq --raw-output --arg identity "${highway_identity}" \
        '[.dependencies[] | select(.identity == $identity) | .path] | first // ""'
  )"; then
    fatal "Failed to read where the ${side} swift-highway resolved to"
  fi
  local canonical_dependency_path=""
  if [[ -n "${dependency_path}" ]]; then
    canonical_dependency_path="$(canonical_directory "${dependency_path}")"
  fi
  local canonical_expected_path
  canonical_expected_path="$(canonical_directory "${expected_directory}")"
  if [[ "${canonical_dependency_path}" != "${canonical_expected_path}" ]]; then
    fatal "The ${side} swift-highway resolved to '${dependency_path}'" \
      "instead of '${expected_directory}'"
  fi
  return 0
}

prepare_side() {
  local side="${1:?prepare_side requires the name of the side}"
  local reference="${2:?prepare_side requires the swift-highway reference}"

  local side_directory="${workspace}/${side}"
  local package_directory="${side_directory}/${repository_root##*/}"
  local scratch_directory="${side_directory}/scratch"
  local dependency_directory="${side_directory}/dependencies/${highway_identity}"

  log "Copying the swift-idna working tree for the ${side} swift-highway..."
  copy_directory "${repository_root}" "${package_directory}"

  local declaration revision="" source_directory=""
  if [[ "${reference}" == "${path_reference_prefix}"* ]]; then
    source_directory="${reference#"${path_reference_prefix}"}"
    if [[ ! -f "${source_directory}/Package.swift" ]]; then
      fatal "There is no Package.swift in the swift-highway directory '${source_directory}'"
    fi
    source_directory="$(canonical_directory "${source_directory}")"
    assert_embeddable_path "${dependency_directory}" "directory of the ${side} swift-highway copy"

    log "Copying the swift-highway directory '${source_directory}' as ${highway_identity}..."
    copy_directory "${source_directory}" "${dependency_directory}"
    declaration=".package(path: \"${dependency_directory}\")"
    description_of_side["${side}"]="${reference}"
  else
    revision="$(resolve_git_revision "${reference}")"
    declaration=".package(url: \"${highway_url}\", revision: \"${revision}\")"
    description_of_side["${side}"]="${reference} (${revision:0:7})"
  fi

  local manifest_file
  local manifest_total=0
  while IFS= read -r -d '' manifest_file; do
    rewrite_highway_dependency "${manifest_file}" "${declaration}"
    manifest_total=$(( manifest_total + 1 ))
  done < <(list_manifest_files "${package_directory}")
  if [[ "${manifest_total}" -eq 0 ]]; then
    fatal "Found no Package.swift or Package@swift-*.swift in '${package_directory}'"
  fi

  local resolved_source="${repository_root}/${resolved_file_name}"
  if [[ ! -f "${resolved_source}" ]]; then
    fatal "There is no '${resolved_source}' to hold the other dependencies identical with" \
      "Run 'swift package resolve' first"
  fi
  write_pinned_resolved_file "${resolved_source}" "${package_directory}/${resolved_file_name}"

  log "Resolving the dependencies of the ${side} swift-highway..."
  if ! swift package resolve --package-path "${package_directory}" \
    --scratch-path "${scratch_directory}" >&2; then
    fatal "Failed to resolve the dependencies with the ${side} swift-highway '${reference}'"
  fi

  verify_held_pins "${side}" "${package_directory}/${resolved_file_name}"
  if [[ -n "${revision}" ]]; then
    verify_git_highway "${side}" "${package_directory}/${resolved_file_name}" "${revision}"
  else
    verify_path_highway "${side}" "${package_directory}" "${scratch_directory}" \
      "${dependency_directory}"
  fi

  package_directory_of_side["${side}"]="${package_directory}"
  scratch_directory_of_side["${side}"]="${scratch_directory}"
  return 0
}

build_target() {
  local side="${1:?build_target requires the name of the side}"
  local target_label="${2:?build_target requires the label of the target}"
  local -n object_files_ref="${3:?build_target requires the name of the object file array}"

  local -a target_arguments=()
  mapfile -d '' -t target_arguments < <(print_target_build_arguments "${target_label}")
  local -a build_arguments=(
    -c release
    --build-system native
    --package-path "${package_directory_of_side["${side}"]}"
    --scratch-path "${scratch_directory_of_side["${side}"]}"
    --force-resolved-versions
    --target "${target_name}"
    "${target_arguments[@]}"
  )

  log "Building ${target_name} of the ${side} swift-highway for ${target_label}..."
  if ! swift build "${build_arguments[@]}" >&2; then
    fatal "Failed to build '${target_name}' with the ${side} swift-highway for ${target_label}"
  fi

  local binary_directory
  if ! binary_directory="$(swift build "${build_arguments[@]}" --show-bin-path)"; then
    fatal "Failed to resolve where '${target_name}' is built to"
  fi

  local object_directory="${binary_directory}/${target_name}.build"
  if [[ ! -d "${object_directory}" ]]; then
    fatal "There is no '${object_directory}' to read the object files of '${target_name}' from"
  fi

  object_files_ref=()
  local object_file
  while IFS= read -r -d '' object_file; do
    object_files_ref+=( "${object_file}" )
  done < <(find "${object_directory}" -name '*.o' -type f -print0 | sort -z)

  if [[ "${#object_files_ref[@]}" -eq 0 ]]; then
    fatal "Found no object files of '${target_name}' under '${object_directory}'"
  fi
  return 0
}

compare_target() {
  local target_label="${1:?compare_target requires the label of the target}"

  local -a old_object_files=()
  local -a new_object_files=()
  build_target old "${target_label}" old_object_files
  build_target new "${target_label}" new_object_files

  local -a compare_arguments=()
  if [[ "${verbose}" == "true" ]]; then
    compare_arguments+=( --verbose )
  fi

  printf -- '== %s: %s -> %s ==\n' \
    "${target_label}" "${description_of_side["old"]}" "${description_of_side["new"]}"
  local compare_status=0
  "${compare_script}" "${compare_arguments[@]}" \
    "${old_object_files[@]}" -- "${new_object_files[@]}" || compare_status="$?"
  case "${compare_status}" in
    0 | 1)
      ;;
    *)
      fatal "'${compare_script##*/}' failed on ${target_label} with status ${compare_status}"
      ;;
  esac
  return "${compare_status}"
}

main() {
  require_command swift
  require_command git
  require_command jq
  require_command rsync

  parse_arguments "$@"
  detect_targets

  if [[ ! -x "${compare_script}" ]]; then
    fatal "There is no executable '${compare_script#"${repository_root}/"}'" \
      "to compare the object files with"
  fi
  if ! "${normalize_script}" --check; then
    fatal "Cannot normalize the disassembly of '${target_name}' without an objdump"
  fi

  workspace="$(mktemp -d)" || fatal "Failed to create a temporary directory for the builds"
  trap cleanup EXIT

  prepare_side old "${old_reference}"
  prepare_side new "${new_reference}"

  local target_label compare_status
  local -a verdicts=()
  local differs="false"
  for target_label in "${target_labels[@]}"; do
    compare_status=0
    compare_target "${target_label}" || compare_status="$?"
    if [[ "${compare_status}" -eq 0 ]]; then
      verdicts+=( "$(printf -- '%-6s %s' "${target_label}" "identical")" )
    else
      differs="true"
      verdicts+=( "$(printf -- '%-6s %s' "${target_label}" "differs")" )
    fi
    printf -- '\n'
  done

  printf -- '%s\n' "${verdicts[@]}"
  if [[ "${differs}" == "true" ]]; then
    exit 1
  fi
  return 0
}

main "$@"
