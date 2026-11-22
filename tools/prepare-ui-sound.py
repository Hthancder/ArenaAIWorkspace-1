#!/usr/bin/env python3
"""Produce a canonical, bounded WAV for a DSolution UI event (no dependencies)."""
import argparse
import sys
import wave

LIMITS = {"select": 250, "back": 250, "success": 1000, "warning": 1000, "find": 1000}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("event", choices=LIMITS)
    parser.add_argument("source", help="16-bit PCM WAV, 48 kHz, mono or stereo")
    parser.add_argument("destination", help="output file, e.g. select.wav")
    parser.add_argument("--trim", action="store_true", help="trim audio to the event's maximum length")
    args = parser.parse_args()
    try:
        with wave.open(args.source, "rb") as src:
            channels, width, rate = src.getnchannels(), src.getsampwidth(), src.getframerate()
            if channels not in (1, 2) or width != 2 or rate != 48000 or src.getcomptype() != "NONE":
                raise ValueError("Input must be uncompressed PCM, 16-bit, 48000 Hz, mono or stereo.")
            count = src.getnframes()
            limit = 48000 * LIMITS[args.event] // 1000
            if not count:
                raise ValueError("Input is empty.")
            if count > limit and not args.trim:
                raise ValueError(f"Too long: {LIMITS[args.event]} ms maximum; use --trim or edit the file.")
            samples = src.readframes(min(count, limit))
            if len(samples) != min(count, limit) * channels * 2:
                raise ValueError("Input WAV is truncated.")
        with wave.open(args.destination, "wb") as dst:
            dst.setnchannels(channels)
            dst.setsampwidth(2)
            dst.setframerate(48000)
            dst.writeframes(samples)
        print(f"Prepared {args.destination}; upload as /ui-sounds/{args.event}.wav in LittleFS.")
    except (OSError, EOFError, wave.Error, ValueError) as error:
        print(f"Cannot prepare sound: {error}", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
