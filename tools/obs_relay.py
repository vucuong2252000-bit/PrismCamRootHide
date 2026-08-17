#!/usr/bin/env python3
"""Forward OBS Virtual Camera frames to PrismCam using an authenticated MJPEG stream."""

from __future__ import annotations

import argparse
import shlex
import socket
import subprocess
import sys
import threading


if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")


def stderr_forwarder(stream) -> None:
    for line in iter(stream.readline, b""):
        sys.stderr.buffer.write(line)
        sys.stderr.buffer.flush()


def build_ffmpeg_command(args: argparse.Namespace) -> list[str]:
    if args.ffmpeg_args:
        command = [args.ffmpeg, *shlex.split(args.ffmpeg_args)]
    elif sys.platform == "win32":
        command = [
            args.ffmpeg,
            "-hide_banner",
            "-loglevel",
            "warning",
            "-f",
            "dshow",
            "-i",
            "video=OBS Virtual Camera",
        ]
    elif sys.platform == "darwin":
        if args.avfoundation_index is None:
            raise SystemExit("macOS cần --avfoundation-index; chạy `ffmpeg -f avfoundation -list_devices true -i ''` để xem số thiết bị.")
        command = [
            args.ffmpeg,
            "-hide_banner",
            "-loglevel",
            "warning",
            "-f",
            "avfoundation",
            "-i",
            f"{args.avfoundation_index}:none",
        ]
    else:
        if not args.video_device:
            raise SystemExit("Linux cần --video-device, ví dụ /dev/video2.")
        command = [
            args.ffmpeg,
            "-hide_banner",
            "-loglevel",
            "warning",
            "-f",
            "v4l2",
            "-i",
            args.video_device,
        ]
    command += [
        "-an",
        "-vf",
        f"fps={args.fps},scale={args.width}:-2",
        "-q:v",
        str(args.quality),
        "-f",
        "image2pipe",
        "-vcodec",
        "mjpeg",
        "pipe:1",
    ]
    return command


def relay(args: argparse.Namespace) -> None:
    command = build_ffmpeg_command(args)
    print("FFmpeg:", " ".join(shlex.quote(part) for part in command))
    with socket.create_connection((args.phone, args.port), timeout=8) as connection:
        connection.sendall(f"PRISMCAM/1 {args.token}\n".encode("utf-8"))
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert process.stdout is not None
        assert process.stderr is not None
        threading.Thread(target=stderr_forwarder, args=(process.stderr,), daemon=True).start()
        print(f"Đang chuyển OBS tới {args.phone}:{args.port}. Nhấn Ctrl+C để dừng.")
        try:
            while True:
                chunk = process.stdout.read(64 * 1024)
                if not chunk:
                    break
                connection.sendall(chunk)
        except KeyboardInterrupt:
            pass
        finally:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
        if process.returncode not in (0, -15, 1, None):
            raise SystemExit(f"FFmpeg dừng với mã {process.returncode}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phone", required=True, help="Địa chỉ IP LAN của iPhone")
    parser.add_argument("--token", required=True, help="Mã ghép nối hiển thị trong PrismCam")
    parser.add_argument("--port", type=int, default=5600)
    parser.add_argument("--ffmpeg", default="ffmpeg", help="Đường dẫn ffmpeg")
    parser.add_argument("--fps", type=int, default=15)
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--quality", type=int, default=5, choices=range(2, 16))
    parser.add_argument("--avfoundation-index", type=int)
    parser.add_argument("--video-device")
    parser.add_argument(
        "--ffmpeg-args",
        help="Thay toàn bộ phần input của FFmpeg; output MJPEG sẽ được thêm tự động",
    )
    args = parser.parse_args()
    if len(args.token) < 12:
        parser.error("Mã ghép nối không hợp lệ")
    relay(args)


if __name__ == "__main__":
    main()
