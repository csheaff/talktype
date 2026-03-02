#!/usr/bin/env bats

# Test suite for the talktype script.
# All external commands (pw-record, ydotool, etc.) are stubbed
# with simple mocks so we can test the control flow in isolation.

setup() {
    export TALKTYPE_CONFIG="/dev/null"
    export TALKTYPE_DIR="$BATS_TEST_TMPDIR/talktype"
    export TALKTYPE_CMD="$BATS_TEST_DIRNAME/mock-transcribe"
    export WAYLAND_DISPLAY=wayland-0

    # Put mocks on PATH before real commands
    export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"

    # The script under test
    TALKTYPE="$BATS_TEST_DIRNAME/../talktype"

    mkdir -p "$TALKTYPE_DIR"
}

teardown() {
    # Kill any leftover processes
    for pidfile in rec.pid trans.pid; do
        if [ -f "$TALKTYPE_DIR/$pidfile" ]; then
            kill "$(cat "$TALKTYPE_DIR/$pidfile")" 2>/dev/null || true
        fi
    done
    rm -rf "$TALKTYPE_DIR"
}

# Helper: set up a fake "in-progress recording" state
start_fake_recording() {
    sleep 300 &
    echo $! > "$TALKTYPE_DIR/rec.pid"
    echo "audio data" > "$TALKTYPE_DIR/rec.wav"
    # Write a timestamp 10 seconds in the past (well above cancel threshold)
    echo $(( $(date +%s%N) - 10000000000 )) > "$TALKTYPE_DIR/rec.start"
}

# ── Recording lifecycle ──

@test "first invocation starts recording and creates pid file" {
    run "$TALKTYPE"
    [ "$status" -eq 0 ]
    [ -f "$TALKTYPE_DIR/rec.pid" ]

    # Verify the PID file contains a valid PID
    pid=$(cat "$TALKTYPE_DIR/rec.pid")
    kill -0 "$pid" 2>/dev/null
}

@test "second invocation stops recording and removes pid file" {
    start_fake_recording

    run "$TALKTYPE"
    [ "$status" -eq 0 ]
    [ ! -f "$TALKTYPE_DIR/rec.pid" ]
}

@test "audio file is cleaned up after transcription" {
    start_fake_recording

    run "$TALKTYPE"
    [ "$status" -eq 0 ]
    [ ! -f "$TALKTYPE_DIR/rec.wav" ]
}

# ── Transcription ──

@test "transcribed text is typed via ydotool" {
    start_fake_recording
    export TALKTYPE_TYPE_CMD=ydotool

    run "$TALKTYPE"
    [ "$status" -eq 0 ]

    # ydotool mock logs its args
    [[ "$(cat "$TALKTYPE_DIR/ydotool.log")" == *"hello world"* ]]
}

@test "custom TALKTYPE_CMD is used for transcription" {
    start_fake_recording
    export TALKTYPE_CMD="$BATS_TEST_DIRNAME/mock-transcribe-custom"
    export TALKTYPE_TYPE_CMD=ydotool

    run "$TALKTYPE"
    [ "$status" -eq 0 ]

    [[ "$(cat "$TALKTYPE_DIR/ydotool.log")" == *"custom output"* ]]
}

# ── Empty transcription ──

@test "exits cleanly when no speech is detected" {
    start_fake_recording
    export TALKTYPE_CMD="$BATS_TEST_DIRNAME/mock-transcribe-empty"

    run "$TALKTYPE"
    [ "$status" -eq 0 ]

    # No typing tool should have been called
    [ ! -f "$TALKTYPE_DIR/ydotool.log" ]
    [ ! -f "$TALKTYPE_DIR/wtype.log" ]
}

# ── Error handling ──

@test "stale pid file with dead process still transcribes" {
    # Simulate a crashed recording: PID file points to a dead process
    echo "99999" > "$TALKTYPE_DIR/rec.pid"
    echo "audio data" > "$TALKTYPE_DIR/rec.wav"
    export TALKTYPE_TYPE_CMD=ydotool

    run "$TALKTYPE"
    [ "$status" -eq 0 ]

    # Should have cleaned up and transcribed
    [ ! -f "$TALKTYPE_DIR/rec.pid" ]
    [[ "$(cat "$TALKTYPE_DIR/ydotool.log")" == *"hello world"* ]]
}

@test "transcription command failure is handled" {
    start_fake_recording
    export TALKTYPE_CMD="$BATS_TEST_DIRNAME/mock-transcribe-fail"

    run "$TALKTYPE"

    # Script exits cleanly — failure is caught by the wait pattern
    [ "$status" -eq 0 ]

    # No typing tool should have been called
    [ ! -f "$TALKTYPE_DIR/ydotool.log" ]
    [ ! -f "$TALKTYPE_DIR/wtype.log" ]
}

# ── Recorder selection ──

@test "ffmpeg is preferred over pw-record when available" {
    run "$TALKTYPE"
    [ "$status" -eq 0 ]
    [ -f "$TALKTYPE_DIR/recorder.log" ]

    [[ "$(cat "$TALKTYPE_DIR/recorder.log")" == "ffmpeg" ]]
}

@test "pw-record is used when ffmpeg is not available" {
    # Remove ffmpeg from PATH by creating a sparse PATH without it
    local sparse="$BATS_TEST_TMPDIR/no_ffmpeg"
    mkdir -p "$sparse"

    # Copy all mocks except ffmpeg
    for mock in "$BATS_TEST_DIRNAME"/mocks/*; do
        name=$(basename "$mock")
        [ "$name" = "ffmpeg" ] && continue
        ln -sf "$mock" "$sparse/$name"
    done

    # Add essential system tools
    for cmd in bash mkdir cat kill sleep echo rm wait; do
        local path
        path=$(command -v "$cmd" 2>/dev/null) && ln -sf "$path" "$sparse/$cmd"
    done

    PATH="$sparse"

    run "$TALKTYPE"
    [ "$status" -eq 0 ]
    [ -f "$TALKTYPE_DIR/recorder.log" ]

    [[ "$(cat "$TALKTYPE_DIR/recorder.log")" == "pw-record" ]]
}

# ── Typing tool selection ──

@test "wtype is preferred on Wayland when available" {
    start_fake_recording

    run "$TALKTYPE"
    [ "$status" -eq 0 ]

    [ -f "$TALKTYPE_DIR/wtype.log" ]
    [ ! -f "$TALKTYPE_DIR/ydotool.log" ]
    [[ "$(cat "$TALKTYPE_DIR/wtype.log")" == *"hello world"* ]]
}

@test "TALKTYPE_TYPE_CMD overrides auto-detection" {
    start_fake_recording
    export TALKTYPE_TYPE_CMD=xdotool

    run "$TALKTYPE"
    [ "$status" -eq 0 ]

    [ -f "$TALKTYPE_DIR/xdotool.log" ]
    [ ! -f "$TALKTYPE_DIR/wtype.log" ]
    [[ "$(cat "$TALKTYPE_DIR/xdotool.log")" == *"hello world"* ]]
}

@test "ydotool is preferred when ydotoold is running" {
    start_fake_recording
    unset WAYLAND_DISPLAY
    export MOCK_PGREP_EXIT=0

    run "$TALKTYPE"
    [ "$status" -eq 0 ]

    [ -f "$TALKTYPE_DIR/ydotool.log" ]
    [ ! -f "$TALKTYPE_DIR/wtype.log" ]
    [[ "$(cat "$TALKTYPE_DIR/ydotool.log")" == *"hello world"* ]]
}

@test "bare ydotool is used as last resort with warning" {
    start_fake_recording
    unset WAYLAND_DISPLAY
    unset DISPLAY

    # Remove wtype and xdotool from PATH so only bare ydotool remains
    local sparse="$BATS_TEST_TMPDIR/bare_ydotool"
    mkdir -p "$sparse"
    for mock in "$BATS_TEST_DIRNAME"/mocks/*; do
        name=$(basename "$mock")
        [ "$name" = "wtype" ] && continue
        [ "$name" = "xdotool" ] && continue
        ln -sf "$mock" "$sparse/$name"
    done
    for cmd in bash mkdir cat kill sleep echo rm touch; do
        local path
        path=$(command -v "$cmd" 2>/dev/null) && ln -sf "$path" "$sparse/$cmd"
    done
    PATH="$sparse"

    run "$TALKTYPE"
    [ "$status" -eq 0 ]

    # Should have typed via ydotool
    [[ "$(cat "$TALKTYPE_DIR/ydotool.log")" == *"hello world"* ]]
    # Warning file should exist
    [ -f "$TALKTYPE_DIR/.ydotool-warned" ]
    # Warning should be in output
    [[ "$output" == *"ydotool without ydotoold"* ]]
}

# ── Dependency checking ──

# ── Cancel mechanisms ──

@test "double-press cancels recording without transcribing" {
    start_fake_recording
    # Overwrite with a fresh timestamp (just now — under 1 second)
    date +%s%N > "$TALKTYPE_DIR/rec.start"

    run "$TALKTYPE"
    [ "$status" -eq 0 ]

    # Should not have transcribed or typed
    [ ! -f "$TALKTYPE_DIR/wtype.log" ]
    [ ! -f "$TALKTYPE_DIR/ydotool.log" ]
    # Audio file should be cleaned up
    [ ! -f "$TALKTYPE_DIR/rec.wav" ]
}

@test "hotkey during transcription cancels it" {
    # Create a fake transcription process
    sleep 300 &
    local trans_pid=$!
    echo "$trans_pid" > "$TALKTYPE_DIR/trans.pid"

    run "$TALKTYPE"
    [ "$status" -eq 0 ]

    # Transcription process should be killed
    ! kill -0 "$trans_pid" 2>/dev/null
    [ ! -f "$TALKTYPE_DIR/trans.pid" ]
}

@test "stale trans.pid falls through to start recording" {
    echo "99999" > "$TALKTYPE_DIR/trans.pid"

    run "$TALKTYPE"
    [ "$status" -eq 0 ]

    # Should have started recording
    [ -f "$TALKTYPE_DIR/rec.pid" ]
    [ ! -f "$TALKTYPE_DIR/trans.pid" ]
}

# ── Dependency checking ──

@test "fails when no typing tool is available" {
    # Create a minimal PATH with only recorder + notify (no typing tools)
    local sparse="$BATS_TEST_TMPDIR/sparse_path"
    mkdir -p "$sparse"
    ln -sf "$BATS_TEST_DIRNAME/mocks/pw-record" "$sparse/pw-record"
    ln -sf "$BATS_TEST_DIRNAME/mocks/notify-send" "$sparse/notify-send"
    ln -sf "$BATS_TEST_DIRNAME/mocks/pgrep" "$sparse/pgrep"
    for cmd in bash mkdir cat kill sleep echo rm; do
        local path
        path=$(command -v "$cmd" 2>/dev/null) && ln -sf "$path" "$sparse/$cmd"
    done

    PATH="$sparse"

    run "$TALKTYPE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing"* ]]
}
