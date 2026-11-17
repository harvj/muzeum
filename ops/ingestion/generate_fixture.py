#!/usr/bin/env python3
"""Independent deterministic corpus/manifest generator. Synthetic data only."""
import argparse, hashlib, json, math, uuid
from pathlib import Path
from xml.sax.saxutils import escape

SEED = 120026
COUNT = 250_000
START = 1_136_073_600
STEP = 2100

def event(i):
    artist = f"Artist {i % 4626}" + (" café 東京" if i % 17 == 0 else "")
    album = "" if i % 11 == 0 else f"Album {i % 11387}"
    track = f"Track {i % 51986}" + (" — " + "long title " * 20 if i % 97 == 0 else "")
    return {"artist_name": artist, "artist_mbid": str(uuid.UUID(int=(SEED << 64) + i % 4626)) if i % 3 == 0 else None, "track_name": track, "track_mbid": str(uuid.UUID(int=(SEED << 64) + i % 51986)) if i % 5 == 0 else None,
            "album_name": album, "album_mbid": str(uuid.UUID(int=(SEED << 64) + i % 11387)) if i % 7 == 0 else None, "played_at": START + i * STEP}

def xml_item(e):
    artist_attribute = f' mbid="{e["artist_mbid"]}"' if e['artist_mbid'] else ''
    album_attribute = f' mbid="{e["album_mbid"]}"' if e['album_mbid'] else ''
    track_mbid = f'<mbid>{e["track_mbid"]}</mbid>' if e['track_mbid'] else ''
    return f'<track><artist{artist_attribute}>{escape(e["artist_name"])}</artist><name>{escape(e["track_name"])}</name>{track_mbid}<album{album_attribute}>{escape(e["album_name"])}</album><date uts="{e["played_at"]}">fixture UTC</date></track>'


def fingerprint(e):
    data = ["synthetic", e["played_at"], e["artist_name"], e["album_name"], e["track_name"]]
    return hashlib.sha256(json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()

def generate(output, count=COUNT):
    output.mkdir(parents=True, exist_ok=True)
    digest, raw_digest = hashlib.sha256(), hashlib.sha256()
    for i in range(count):
        digest.update((fingerprint(event(i)) + "\n").encode())
    pages = math.ceil(count / 200)
    manifests = []
    for page in range(1, pages + 1):
        indices = range(count - 1 - (page - 1) * 200, max(-1, count - 1 - page * 200), -1)
        items = [event(i) for i in indices]
        raw = (f'<lfm status="ok"><recenttracks user="synthetic" page="{page}" totalPages="{pages}" total="{count}">' + "".join(map(xml_item, items)) + '</recenttracks></lfm>').encode()
        checksum = hashlib.sha256(raw).hexdigest(); raw_digest.update((checksum + "\n").encode())
        (output / f"{page:05}.xml").write_bytes(raw)
        # Prebuilt rows for A: XML parsing excluded; canonical item XML has no namespaces/attributes requiring reordering.
        prebuilt = [{"position": index + 1, "payload": item, "classification": None,
                     "checksum": hashlib.sha256(xml_item(item).encode()).hexdigest()} for index, item in enumerate(items)]
        (output / f"{page:05}.json").write_text(json.dumps(prebuilt, ensure_ascii=False))
        manifests.append({"page": page, "received": len(items), "inserted": len(items), "repeats": 0, "conflicts": 0, "invalid": 0, "now_playing": 0, "sha256": checksum})
    manifest = {"generator": "generate_fixture.py/v2", "seed": SEED, "count": count, "pages": pages,
                "first_timestamp": START, "last_timestamp": START + (count - 1) * STEP,
                "ordered_fingerprint_sha256": digest.hexdigest(), "page_checksum_manifest_sha256": raw_digest.hexdigest(), "page_manifest": manifests}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest

if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument("output", type=Path); parser.add_argument("--count", type=int, default=COUNT)
    args = parser.parse_args(); result = generate(args.output, args.count)
    print(json.dumps({key: value for key, value in result.items() if key != "page_manifest"}, indent=2))
