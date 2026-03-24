#!/usr/bin/env bash

# ------------------------------------------------------------
#  build_check.sh
#
#  Checks the latest GitHub Actions build status.
#  If the checks pass, it pulls the repo, runs CMake,
#  builds with make and logs any failures.
#
#  ------------------------------------------------------------

set -euo pipefail # fail fast, treat unset vars as error
IFS=$'\n\t'

SHOW_SUCCESS=false

while [[ $# -gt 0 ]]; do
	case "$1" in
	--success) SHOW_SUCCESS=true ;;
	*)
		echo "Unknown option: $1" >&2
		exit 1
		;;
	esac
	shift
done

#########################
## Configuration
#########################

# ----- GitHub details -----
GITHUB_REPO="${GITHUB_REPO:-user/repo}" # <--- change to your repo
API_TOKEN="${GITHUB_API_TOKEN:-}"       # optional PAT (needs repo:status)
BASE_URL="${BASE_URL:-https://api.github.com}"
UPDATE_SUBMODULES=${UPDATE_SUBMODULES:-false}

# ----- Build directories -----
REPO_DIR="${REPO_DIR:-/path/to/repo/$(basename "$GITHUB_REPO")}"
BUILD_DIR="${BUILD_DIR:-$REPO_DIR/build}"
LOG_FILE="${LOG_FILE:-/tmp/build_check.log}"
JOBS=${JOBS:-12}

# ----- CMake -----
CMAKE_CONFIG="${CMAKE_CONFIG:-}"

# ----- Mail -----
RECIPIENTS="${RECIPIENTS:-e@mail.com}"
MAIL_CLIENT_SYNTAX="${MAIL_CLIENT_SYNTAX:-}"
# e.g. postfix syntax
#  MAIL_CLIENT_SYNTAX="{MAIL_CLIENT_SYNTAX:-sendmail -t}"

#########################
## Helper functions
#########################
print_last_result() {
	if [[ -f "${LOG_FILE}" ]]; then
		tail -n 1 "${LOG_FILE}"
	else
		echo "No log file found. Have you run the script yet?"
	fi
}

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"${LOG_FILE}"; }

check_github_status() {
	# 1️⃣ Get the latest workflow run for the default branch
	local branch=$(git -C "${REPO_DIR}" rev-parse --abbrev-ref HEAD)
	local runs_url="${BASE_URL}/repos/${GITHUB_REPO}/actions/runs?branch=${branch}&per_page=1"
	local resp
	if [[ -n ${API_TOKEN} ]]; then
		resp=$(curl -sSLH "Authorization: token ${API_TOKEN}" "${runs_url}")
	else
		resp=$(curl -sSL "${runs_url}")
	fi

	# 2️⃣ Extract the conclusion (success / failure / etc.)
	local conclusion
	conclusion=$(echo "${resp}" | jq -r '.workflow_runs[0].conclusion')
	if [[ ${conclusion} == "null" ]]; then
		log "❌ No completed run found for branch '${branch}'."
		return 1
	fi

	if [[ ${conclusion} != "success" ]]; then
		log "⚠️  Latest run concluded with: ${conclusion}."
		return 1
	fi

	log "✅ GitHub Actions build succeeded."
	return 0
}

configure_and_build() {
	mkdir -p "${BUILD_DIR}"
	pushd "${BUILD_DIR}"

	# ---- CMake configure ----
	if ! cmake ${CMAKE_CONFIG} .. >>"${LOG_FILE}" 2>&1; then
		log "❌ CMake configuration failed. Check ${LOG_FILE} for details."
		popd
		return 1
	fi
	log "✅ CMake configuration succeeded."

	# ---- Build with make ----
	if ! make -j${JOBS} >>"${LOG_FILE}" 2>&1; then
		log "❌ Make build failed. See ${LOG_FILE}."
		popd
		return 1
	fi
	log "✅ Build succeeded."
	popd
}

send_email() {
	local subject="$1"
	local body="$2"

	printf "Subject: ${subject}\n\n${body}" | ${MAIL_CLIENT_SYNTAX} ${RECIPIENTS}
}

#########################
## Main flow
#########################

if ${SHOW_SUCCESS}; then
	print_last_result
	if grep -q "✅" "${LOG_FILE}"; then
		exit 0 # success
	else
		exit 1 # failure or unknown
	fi
fi

# If the repo dir does not exist, clone it first
if [[ ! -d "${REPO_DIR}/.git" ]]; then
	log "⚙️  Cloning repository ${GITHUB_REPO} into ${REPO_DIR}"
	git clone --recursive "https://github.com/${GITHUB_REPO}.git" "${REPO_DIR}"
fi

# Pull the latest changes
log "🔄 Pulling latest commits."
git -C "${REPO_DIR}" fetch --all
git -C "${REPO_DIR}" reset --hard origin/$(git -C "${REPO_DIR}" rev-parse --abbrev-ref HEAD)
if ${UPDATE_SUBMODULES}; then
    git -C "${REPO_DIR}" submodule sync --recursive
    git -C "${REPO_DIR}" submodule update --init --recursive
fi

# Check GitHub build status
if ! check_github_status; then
	exit 1
fi

# If the checks passed, run local build
if ! configure_and_build; then

	if ! rm -rf "${BUILD_DIR}"; then
		send_email "Build FAILED on $(hostname)" \
			"Something went wrong during the nightly build of ${GITHUB_REPO}. A clean build could not be tried.\nCheck ${LOG_FILE} for details."
		exit 1
	fi

	if ! configure_and_build; then
		send_email "Build FAILED on $(hostname)" \
			"Something went wrong during the nightly build of ${GITHUB_REPO}, even after a clean build.\nCheck ${LOG_FILE} for details."
		exit 1
	fi
fi
# else
# send_email "✅ Build succeeded on $(hostname)" \
#     "The daily build for ${GITHUB_REPO} finished successfully.\n\nSee $LOG_FILE for details."
# fi

log "🎉 All steps completed successfully."
exit 0
