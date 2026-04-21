#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: create-linode-image.sh --linode <id-or-label> --label <image-label> [options]

Options:
  --description <text>  Optional image description.
  --tag <tag>           Optional image tag. Repeatable.
  --cloud-init          Mark the image as cloud-init capable.
  --keep-running        Do not stop the Linode before imaging or boot it afterwards.

The script resolves the target Linode, selects the first non-swap disk, creates a
private image, and prints the resulting image ID.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require_cmd linode-cli
require_cmd jq

linode_ref=""
image_label=""
description=""
cloud_init=0
keep_running=0
declare -a tags=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --linode)
      linode_ref="${2:-}"
      shift 2
      ;;
    --label)
      image_label="${2:-}"
      shift 2
      ;;
    --description)
      description="${2:-}"
      shift 2
      ;;
    --tag)
      tags+=("${2:-}")
      shift 2
      ;;
    --cloud-init)
      cloud_init=1
      shift
      ;;
    --keep-running)
      keep_running=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ -n "${linode_ref}" ]] || {
  usage >&2
  exit 1
}
[[ -n "${image_label}" ]] || {
  usage >&2
  exit 1
}

resolve_linode_id() {
  if [[ "${linode_ref}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "${linode_ref}"
    return 0
  fi

  linode-cli linodes list --json \
    | jq -r --arg label "${linode_ref}" '
        map(select(.label == $label)) | .[0].id // empty
      '
}

linode_id="$(resolve_linode_id)"
[[ -n "${linode_id}" ]] || {
  echo "could not resolve Linode: ${linode_ref}" >&2
  exit 1
}

linode_json="$(linode-cli linodes view "${linode_id}" --json | jq '.[0]')"
linode_label="$(jq -r '.label' <<<"${linode_json}")"
linode_status="$(jq -r '.status' <<<"${linode_json}")"

disk_id="$(
  linode-cli linodes disks-list "${linode_id}" --json \
    | jq -r '
        map(select(.filesystem != "swap")) | sort_by(.id) | .[0].id // empty
      '
)"
[[ -n "${disk_id}" ]] || {
  echo "could not find a non-swap disk on Linode ${linode_label} (${linode_id})" >&2
  exit 1
}

should_boot_after=0
if [[ "${keep_running}" -eq 0 && "${linode_status}" == "running" ]]; then
  echo "Shutting down ${linode_label} (${linode_id}) before image capture"
  linode-cli linodes shutdown "${linode_id}" >/dev/null
  should_boot_after=1

  for _ in $(seq 1 60); do
    current_status="$(
      linode-cli linodes view "${linode_id}" --json | jq -r '.[0].status'
    )"
    if [[ "${current_status}" == "offline" ]]; then
      break
    fi
    sleep 5
  done

  current_status="$(
    linode-cli linodes view "${linode_id}" --json | jq -r '.[0].status'
  )"
  [[ "${current_status}" == "offline" ]] || {
    echo "timed out waiting for ${linode_label} to power off" >&2
    exit 1
  }
fi

declare -a create_args=(
  --disk_id "${disk_id}"
  --label "${image_label}"
)

if [[ -n "${description}" ]]; then
  create_args+=(--description "${description}")
fi

if [[ "${cloud_init}" -eq 1 ]]; then
  create_args+=(--cloud_init true)
fi

if [[ "${#tags[@]}" -gt 0 ]]; then
  create_args+=(--tags "$(IFS=,; echo "${tags[*]}")")
fi

image_json="$(linode-cli images create "${create_args[@]}" --json | jq '.[0]')"
image_id="$(jq -r '.id' <<<"${image_json}")"
image_status="$(jq -r '.status // "pending"' <<<"${image_json}")"

if [[ "${should_boot_after}" -eq 1 ]]; then
  echo "Booting ${linode_label} (${linode_id}) after image capture request"
  linode-cli linodes boot "${linode_id}" >/dev/null
fi

echo "Created image ${image_id} from ${linode_label} (${linode_id}), disk ${disk_id}"
echo "Image status: ${image_status}"
echo "Use gpu_worker_image = \"${image_id}\" and gpu_worker_bootstrap_mode = \"prebaked\" in terraform.tfvars"
