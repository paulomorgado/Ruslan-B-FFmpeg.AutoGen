#!/usr/bin/env sh

set -eu

Version="8.1"
DestinationFolder=""
IncludeExes="false"
Force="false"

ShowUsage() {
    cat <<'USAGE'
Downloads FFmpeg shared libraries for application run-time use.

Usage:
  ./download-ffmpeg-runtime.sh --destination-folder <path> [options]

Options:
  -v, --version <version>              FFmpeg release tag on GyanD/codexffmpeg (default: 8.1).
  -d, --destination-folder <path>      Destination folder for the FFmpeg binaries.
      --include-exes                   Also copy .exe files from the FFmpeg bin directory.
  -f, --force                          Overwrite existing FFmpeg binaries.
  -h, --help                           Show this help text.

Examples:
  ./download-ffmpeg-runtime.sh --destination-folder ./bin/x64
  ./download-ffmpeg-runtime.sh --version 8.1 --destination-folder ./publish --include-exes --force
USAGE
}

WriteError() {
    printf '%s\n' "$1" >&2
}

RequireValue() {
    if [ "$#" -eq 0 ] || [ -z "$1" ]; then
        WriteError "Expected a value for $2."
        exit 1
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -v|--version)
            shift
            RequireValue "$@" "--version"
            Version="$1"
            ;;
        -d|--destination-folder)
            shift
            RequireValue "$@" "--destination-folder"
            DestinationFolder="$1"
            ;;
        --include-exes)
            IncludeExes="true"
            ;;
        -f|--force)
            Force="true"
            ;;
        -h|--help)
            ShowUsage
            exit 0
            ;;
        *)
            WriteError "Unknown argument: $1"
            ShowUsage >&2
            exit 1
            ;;
    esac

    shift
done

if [ -z "$DestinationFolder" ]; then
    WriteError "Missing required option: --destination-folder."
    ShowUsage >&2
    exit 1
fi

mkdir -p "$DestinationFolder"
DestinationFolderPath=$(cd "$DestinationFolder" && pwd -P)

if [ "$Force" != "true" ]; then
    for ExistingDll in "$DestinationFolderPath"/avcodec-*.dll; do
        if [ -f "$ExistingDll" ]; then
            printf 'FFmpeg DLLs already exist in %s\n' "$DestinationFolderPath"
            printf '%s\n' "Re-run with --force to overwrite, or delete the existing FFmpeg DLLs manually."
            exit 0
        fi
    done
fi

ArchiveName="ffmpeg-$Version-full_build-shared.zip"
Url="https://github.com/GyanD/codexffmpeg/releases/download/$Version/$ArchiveName"
TempDir=$(mktemp -d "${TMPDIR:-/tmp}/ffmpeg-autogen.XXXXXX")

Cleanup() {
    if [ -n "${TempDir:-}" ] && [ -d "$TempDir" ]; then
        rm -rf "$TempDir"
    fi
}

trap Cleanup EXIT INT TERM

ArchivePath="$TempDir/$ArchiveName"

if ! command -v unzip >/dev/null 2>&1; then
    WriteError "unzip is required to extract FFmpeg."
    exit 1
fi

printf 'Downloading FFmpeg %s from %s\n' "$Version" "$Url"

if command -v curl >/dev/null 2>&1; then
    if ! curl --fail --location --output "$ArchivePath" "$Url"; then
        WriteError "Failed to download FFmpeg $Version. URL: $Url"
        exit 1
    fi
elif command -v wget >/dev/null 2>&1; then
    if ! wget --output-document "$ArchivePath" "$Url"; then
        WriteError "Failed to download FFmpeg $Version. URL: $Url"
        exit 1
    fi
else
    WriteError "curl or wget is required to download FFmpeg."
    exit 1
fi

printf '%s\n' "Extracting..."
unzip -q "$ArchivePath" -d "$TempDir"

ExtractedDir=""
for CandidateDir in "$TempDir"/ffmpeg-*; do
    if [ -d "$CandidateDir" ]; then
        ExtractedDir="$CandidateDir"
        break
    fi
done

if [ -z "$ExtractedDir" ]; then
    WriteError "Could not find extracted FFmpeg directory in $TempDir"
    exit 1
fi

BinarySource="$ExtractedDir/bin"
if [ ! -d "$BinarySource" ]; then
    WriteError "Expected bin directory not found: $BinarySource"
    exit 1
fi

DllCount=0
for DllFile in "$BinarySource"/*.dll; do
    if [ -f "$DllFile" ]; then
        DllCount=$((DllCount + 1))
    fi
done

if [ "$DllCount" -eq 0 ]; then
    WriteError "No DLL files found in $BinarySource"
    exit 1
fi

printf 'Copying DLLs to %s\n' "$DestinationFolderPath"
for DllFile in "$BinarySource"/*.dll; do
    if [ -f "$DllFile" ]; then
        cp -f "$DllFile" "$DestinationFolderPath"
    fi
done

ExeCount=0
if [ "$IncludeExes" = "true" ]; then
    for ExeFile in "$BinarySource"/*.exe; do
        if [ -f "$ExeFile" ]; then
            ExeCount=$((ExeCount + 1))
        fi
    done

    printf 'Copying EXEs to %s\n' "$DestinationFolderPath"
    for ExeFile in "$BinarySource"/*.exe; do
        if [ -f "$ExeFile" ]; then
            cp -f "$ExeFile" "$DestinationFolderPath"
        fi
    done
fi

Summary="Done! FFmpeg $Version: $DllCount DLLs"
if [ "$IncludeExes" = "true" ]; then
    Summary="$Summary, $ExeCount EXEs"
fi

printf '%s copied to %s.\n' "$Summary" "$DestinationFolderPath"
