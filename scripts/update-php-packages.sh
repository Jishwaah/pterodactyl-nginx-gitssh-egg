#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_PHP_SERIES="${PHP_VERSION:-8.4}"
readonly SURY_SOURCE_FILE="/etc/apt/sources.list.d/php.list"

if [[ ! "${EXPECTED_PHP_SERIES}" =~ ^8\.[2-5]$ ]]; then
    echo "[PHP Update] ERROR: Supported PHP series are 8.2, 8.3, 8.4 and 8.5; received '${EXPECTED_PHP_SERIES}'."
    exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
    echo "[PHP Update] ERROR: PHP package updates require the container to run as root."
    exit 1
fi

if [[ ! -r "${SURY_SOURCE_FILE}" ]] || ! grep -q 'packages\.sury\.org/php' "${SURY_SOURCE_FILE}"; then
    echo "[PHP Update] ERROR: The Sury PHP repository is not configured."
    exit 1
fi

list_installed_php_packages() {
    dpkg-query -W -f='${db:Status-Abbrev}\t${Package}\n' "php${EXPECTED_PHP_SERIES}*" 2>/dev/null \
        | awk '$1 == "ii" { print $2 }' \
        | sort -u
}

mapfile -t php_packages < <(list_installed_php_packages)

if (( ${#php_packages[@]} == 0 )); then
    echo "[PHP Update] ERROR: No installed PHP ${EXPECTED_PHP_SERIES} packages were found."
    exit 1
fi

echo "[PHP Update] Refreshing Sury package metadata for PHP ${EXPECTED_PHP_SERIES}..."
updated=false
for attempt in 1 2 3 4 5; do
    if apt-get update; then
        updated=true
        break
    fi

    if (( attempt < 5 )); then
        delay=$((attempt * 5))
        echo "[PHP Update] apt-get update failed (${attempt}/5); retrying in ${delay}s..."
        sleep "${delay}"
    fi
done

if [[ "${updated}" != true ]]; then
    echo "[PHP Update] ERROR: Package metadata could not be refreshed; refusing to start with an unverified PHP build."
    exit 1
fi

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    --only-upgrade \
    --allow-change-held-packages \
    --no-install-recommends \
    "${php_packages[@]}"

# An upgrade can introduce another versioned PHP dependency, so audit a fresh list.
mapfile -t php_packages < <(list_installed_php_packages)

verification_failed=false
for package in "${php_packages[@]}"; do
    installed_package_version="$(dpkg-query -W -f='${Version}' "${package}")"
    candidate_package_version="$(LC_ALL=C apt-cache policy "${package}" | awk '/Candidate:/ { print $2; exit }')"

    if [[ -z "${candidate_package_version}" || "${candidate_package_version}" == "(none)" ]]; then
        echo "[PHP Update] ERROR: ${package} has no package candidate after refreshing Sury."
        verification_failed=true
    elif [[ "${installed_package_version}" != "${candidate_package_version}" ]]; then
        echo "[PHP Update] ERROR: ${package} is ${installed_package_version}; current candidate is ${candidate_package_version}."
        verification_failed=true
    fi
done

if [[ "${verification_failed}" == true ]]; then
    echo "[PHP Update] ERROR: Not every PHP ${EXPECTED_PHP_SERIES} package is at the latest available version."
    exit 1
fi

installed_version="$(php${EXPECTED_PHP_SERIES} -r 'echo PHP_VERSION;')"
if [[ "${installed_version}" != "${EXPECTED_PHP_SERIES}."* ]]; then
    echo "[PHP Update] ERROR: Expected PHP ${EXPECTED_PHP_SERIES}.x, but found ${installed_version}."
    exit 1
fi

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "[PHP Update] PHP ${installed_version} is installed; every PHP ${EXPECTED_PHP_SERIES} package matches the latest Sury/APT candidate."
